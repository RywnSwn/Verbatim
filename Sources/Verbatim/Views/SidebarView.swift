import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(RecorderModel.self) private var model
    @State private var renaming: RecordingInfo?
    @State private var newTitle = ""

    var body: some View {
        @Bindable var model = model
        Group {
            if model.recordings.isEmpty {
                VStack(alignment: .leading) {
                    Text("Your recordings will show up here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            } else {
                List(selection: $model.selection) {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.items) { info in
                                SidebarRow(info: info, isLive: info.id == model.currentID)
                                    .tag(info.id)
                                    .contextMenu {
                                        Button("Rename…") {
                                            newTitle = info.title
                                            renaming = info
                                        }
                                        Button("Show in Finder") { model.showInFinder(info) }
                                        Divider()
                                        if info.id != model.currentID {
                                            Button(info.hasAudio ? "Play Audio" : "Audio Deleted") { model.playAudio(info.id) }
                                                .disabled(!info.hasAudio)
                                        }
                                        Button(SidebarView.deleteAudioTitle(info, blocker: model.audioDeleteBlocker(info.id))) {
                                            model.deleteAudio(info.id)
                                        }
                                        .disabled(model.audioDeleteBlocker(info.id) != nil)
                                        if info.hasAudio, info.id != model.currentID {
                                            Toggle("Keep Audio", isOn: Binding(
                                                get: { info.keepAudio == true },
                                                set: { model.setKeepAudio(info.id, $0) }))
                                        }
                                        Divider()
                                        Button("Delete") { model.delete(info.id) }
                                            .keyboardShortcut(.delete, modifiers: .command)
                                            .disabled(!model.canDelete(info.id))
                                    }
                            }
                        }
                    }
                }
                .onDeleteCommand {
                    if let id = model.selection { model.delete(id) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            NewRecordingButton()
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .padding(.bottom, 6)
                RecentlyDeletedButton()
                HStack {
                    Button {
                        model.chooseFilesToImport()
                    } label: {
                        Label("Transcribe a file…", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Pick a Voice Memo or other recording to turn into text (⌘O)")
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Settings: microphone and updates (⌘,)")
                    .accessibilityLabel("Settings")
                }
                Text("Or drop a Voice Memo anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Rename") {
                if let r = renaming { model.rename(r.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    /// "Delete Audio Only (115 MB)", so it's clear what you get back,
    /// or why it can't be used right now.
    static func deleteAudioTitle(_ info: RecordingInfo, blocker: String?) -> String {
        if !info.hasAudio { return "Delete Audio Only (already deleted)" }
        if let blocker { return "Delete Audio Only (\(blocker.lowercased()))" }
        guard let bytes = RecordingStore.audioSize(info.id) else { return "Delete Audio Only" }
        return "Delete Audio Only (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
    }

    private var groups: [SidebarGroup] {
        let cal = Calendar.current
        let now = Date()
        var today: [RecordingInfo] = [], week: [RecordingInfo] = [], earlier: [RecordingInfo] = []
        for r in model.recordings {
            if cal.isDateInToday(r.createdAt) {
                today.append(r)
            } else if let days = cal.dateComponents([.day], from: r.createdAt, to: now).day, days < 7 {
                week.append(r)
            } else {
                earlier.append(r)
            }
        }
        return [SidebarGroup(title: "Today", items: today), SidebarGroup(title: "This week", items: week), SidebarGroup(title: "Earlier", items: earlier)]
            .filter { !$0.items.isEmpty }
    }
}

struct SidebarGroup: Identifiable {
    let title: String
    let items: [RecordingInfo]
    var id: String { title }
}

struct SidebarRow: View {
    let info: RecordingInfo
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(info.title)
                .font(.body.weight(.medium))
            Group {
                if isLive { LiveRowMeta() } else { Text(meta) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        let day = info.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let base = "\(day), \(RecorderModel.minutesText(info.duration))"
        if !info.hasAudio { return base + ", no audio" }
        // Step 9: a warning a few days before old audio goes.
        if let left = AudioCleanup.daysLeft(info), left <= 3 {
            return day + (left <= 1 ? ", audio deletes tomorrow" : ", audio deletes in \(left) days")
        }
        return base
    }
}

/// "Recording now, 12 min". Its own view so the ticking clock redraws only
/// this bit of text, not the whole sidebar.
struct LiveRowMeta: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        let len = RecorderModel.minutesText(model.elapsed)
        Text(model.phase == .paused ? "Paused, \(len)" : "Recording now, \(len)")
    }
}

/// Always at the top of the sidebar, like "New chat" in Claude.
/// Opens the start screen (recording begins from its Start button, Ryan's
/// ask); while recording it jumps back to it.
struct NewRecordingButton: View {
    @Environment(RecorderModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.showNewRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.isBusy ? "waveform" : "plus")
                    .fontWeight(.semibold)
                    .frame(width: 16)
                Text(model.isBusy ? (model.phase == .paused ? "Paused, go to it" : "Recording now") : "New recording")
                    .fontWeight(.medium)
                Spacer()
                if !model.isBusy {
                    Text("⌘N")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(model.isBusy ? "Go to the recording in progress" : "Open a new recording (⌘N)")
    }
}

/// "Recently deleted (3)" at the bottom of the sidebar (step 9). Hidden when empty.
struct RecentlyDeletedButton: View {
    @Environment(RecorderModel.self) private var model
    private var deleted: RecentlyDeleted { .shared }

    var body: some View {
        if !deleted.items.isEmpty {
            Button {
                model.selection = nil
                model.showingDeleted = true
            } label: {
                Label("Recently deleted (\(deleted.items.count))", systemImage: "trash")
                    .fontWeight(model.showingDeleted ? .semibold : .regular)
            }
            .buttonStyle(.borderless)
            .help("Deleted recordings stay here for \(RecentlyDeleted.keepDays) days")
        }
    }
}
