import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Step 10: like the sidebar in Claude. Groups (one per class) with an icon
/// and a + to record right in them, then Recents for everything not in a
/// group. Right-click empty space for New Group; right-click a recording to
/// move it, or drag it onto a group (its name or any recording in it).
/// Dragged out of Verbatim (to Claude, Finder, Notes) a recording becomes
/// a Markdown file of its transcript.
struct SidebarView: View {
    @Environment(RecorderModel.self) private var model
    @State private var renaming: RecordingInfo?
    @State private var newTitle = ""
    @State private var groupDraft = ""
    @State private var iconFor: UUID?
    @AppStorage("recentsCollapsed") private var recentsCollapsed = false

    private var store: GroupStore { .shared }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            // Inside the list (not a top inset), so they sit below the window's
            // buttons instead of under them (Ryan saw them overlap on macOS 26).
            Section {
                NewRecordingButton()
                SidebarAction(title: "Add a Voice Memo", icon: "waveform.badge.plus", shortcut: "⌘O",
                              help: "Pick a Voice Memo or other recording to turn into text. Or drop one anywhere.") {
                    model.chooseFilesToImport()
                }
                RecentlyDeletedButton()
            }
            .selectionDisabled()
            .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))

            // A line between the actions and the groups, like Claude's sidebar.
            Divider()
                .padding(.vertical, 6)
                .selectionDisabled()
                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))

            // Each group is a fold-down zone: bold name and arrow, its
            // recordings indented under it. Not the list's own folding, which
            // only shows an arrow on hover at the far side.
            ForEach(store.groups) { group in
                Section {
                    if !group.collapsed {
                        let members = model.recordings.filter { $0.groupID == group.id }
                        if members.isEmpty {
                            Text(model.isBusy ? "Empty. Drag a recording here." : "Empty. Press + or drag one here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 22)
                                .selectionDisabled()
                                .dropDestination(for: RecordingDrag.self) { items, _ in move(items, to: group.id) }
                        }
                        ForEach(members) { info in
                            row(info, indent: true)
                                .dropDestination(for: RecordingDrag.self) { items, _ in move(items, to: group.id) }
                        }
                    }
                } header: {
                    GroupHeader(group: group)
                }
            }

            Section {
                if !recentsCollapsed {
                    let recents = model.recordings.filter { store.group($0.groupID) == nil }
                    if model.recordings.isEmpty {
                        Text("Your recordings will show up here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(recents) { info in
                        row(info, indent: false)
                            .dropDestination(for: RecordingDrag.self) { items, _ in move(items, to: nil) }
                    }
                }
            } header: {
                RecentsHeader(collapsed: $recentsCollapsed)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, ids.count == 1, let info = model.recordings.first(where: { $0.id == id }) {
                recordingMenu(info)
            } else if ids.isEmpty {
                Button("New Group") { newGroup() }
            }
        }
        .onDeleteCommand {
            if let id = model.selection { model.delete(id) }
        }
        .animation(.snappy(duration: 0.25), value: store.groups)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Right-click empty space for a new group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Rename") {
                if let r = renaming { model.rename(r.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Name this group", isPresented: Binding(
            get: { model.renameGroupRequest != nil },
            set: { if !$0 { model.renameGroupRequest = nil } })
        ) {
            TextField("Like English 2026", text: $groupDraft)
            Button("OK") {
                if let id = model.renameGroupRequest { store.rename(id, to: groupDraft) }
                model.renameGroupRequest = nil
            }
            Button("Cancel", role: .cancel) { model.renameGroupRequest = nil }
        } message: {
            Text("One group per class works well. Pick an icon by clicking the one next to its name.")
        }
        .onChange(of: model.renameGroupRequest) {
            if let id = model.renameGroupRequest { groupDraft = store.group(id)?.name ?? "" }
        }
    }

    private func move(_ items: [RecordingDrag], to groupID: UUID?) -> Bool {
        for item in items { model.moveRecording(item.id, to: groupID) }
        return !items.isEmpty
    }

    private func newGroup() {
        let group = store.add()
        model.renameGroupRequest = group.id
    }

    private func row(_ info: RecordingInfo, indent: Bool) -> some View {
        SidebarRow(info: info, isLive: info.id == model.currentID)
            .padding(.leading, indent ? 22 : 0)
            .tag(info.id)
            .draggable(RecordingDrag(id: info.id)) {
                Label(info.title, systemImage: "doc.text")
                    .padding(6)
            }
            .popover(isPresented: Binding(get: { iconFor == info.id }, set: { if !$0 { iconFor = nil } }),
                     arrowEdge: .trailing) {
                IconPicker(icon: info.icon, color: info.iconColor ?? .ink) { icon, color in
                    model.setIcon(info.id, icon, color: color)
                }
            }
    }

    @ViewBuilder private func recordingMenu(_ info: RecordingInfo) -> some View {
        Button("Rename…") {
            newTitle = info.title
            renaming = info
        }
        Button("Change Icon…") { iconFor = info.id }
        Menu("Move to Group") {
            ForEach(store.groups) { group in
                Button(group.name) { model.moveRecording(info.id, to: group.id) }
                    .disabled(info.groupID == group.id)
            }
            if !store.groups.isEmpty { Divider() }
            Button("Recents (no group)") { model.moveRecording(info.id, to: nil) }
                .disabled(store.group(info.groupID) == nil)
            Divider()
            Button("New Group…") {
                let group = store.add()
                model.moveRecording(info.id, to: group.id)
                model.renameGroupRequest = group.id
            }
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

    /// "Delete Audio Only (115 MB)", so it's clear what you get back,
    /// or why it can't be used right now.
    static func deleteAudioTitle(_ info: RecordingInfo, blocker: String?) -> String {
        if !info.hasAudio { return "Delete Audio Only (already deleted)" }
        if let blocker { return "Delete Audio Only (\(blocker.lowercased()))" }
        guard let bytes = RecordingStore.audioSize(info.id) else { return "Delete Audio Only" }
        return "Delete Audio Only (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
    }
}

/// A group's name in the sidebar: its icon (click to change), the name, and +
/// to start a recording in it. Drop a recording on it to move it in.
struct GroupHeader: View {
    @Environment(RecorderModel.self) private var model
    let group: RecordingGroup
    @State private var picking = false
    @State private var targeted = false

    private var store: GroupStore { .shared }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                picking = true
            } label: {
                ItemIcon(name: group.icon, color: group.color, size: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change the icon")
            .accessibilityLabel("Change icon for \(group.name)")
            .popover(isPresented: $picking, arrowEdge: .trailing) {
                IconPicker(icon: group.icon, color: group.color) { icon, color in
                    store.update(group.id) {
                        $0.icon = icon
                        $0.color = color
                    }
                }
            }

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    store.update(group.id) { $0.collapsed.toggle() }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(group.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(group.collapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(group.collapsed ? "Show recordings" : "Fold up")
            .accessibilityLabel("\(group.name), \(group.collapsed ? "folded" : "open")")

            Spacer(minLength: 4)

            Button {
                Task { await model.start(in: group.id) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help(model.isBusy ? "Stop the recording first" : "New recording in \(group.name)")
            .accessibilityLabel("New recording in \(group.name)")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(targeted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.top, 8)
        .dropDestination(for: RecordingDrag.self) { items, _ in
            for item in items { model.moveRecording(item.id, to: group.id) }
            if !items.isEmpty, group.collapsed { store.update(group.id) { $0.collapsed = false } }
            return !items.isEmpty
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("New Recording Here") { Task { await model.start(in: group.id) } }
                .disabled(model.isBusy)
            Divider()
            Button("Rename Group…") { model.renameGroupRequest = group.id }
            Button("Change Icon…") { picking = true }
            Divider()
            Button("Move Up") { store.move(group.id, by: -1) }
                .disabled(store.groups.first?.id == group.id)
            Button("Move Down") { store.move(group.id, by: 1) }
                .disabled(store.groups.last?.id == group.id)
            Divider()
            Button("Delete Group") { model.deleteGroup(group.id) }
        }
    }
}

/// "Recents": recordings not in any group, folds like a group. Dropping a
/// recording here takes it out of its group.
struct RecentsHeader: View {
    @Environment(RecorderModel.self) private var model
    @Binding var collapsed: Bool
    @State private var targeted = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text("Recents")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .background(targeted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: RecordingDrag.self) { items, _ in
            for item in items { model.moveRecording(item.id, to: nil) }
            return !items.isEmpty
        } isTargeted: { targeted = $0 }
        .accessibilityLabel("Recents, \(collapsed ? "folded" : "open")")
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

struct SidebarRow: View {
    let info: RecordingInfo
    let isLive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon = info.icon {
                ItemIcon(name: icon, color: info.iconColor ?? .ink, size: 11)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Group {
                    if isLive { LiveRowMeta() } else { Text(meta) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        let day = RecorderModel.dayTitle(info.createdAt)
        // Named after the day already: say the time instead of the day twice.
        let when = info.title.contains(day) ? info.createdAt.formatted(date: .omitted, time: .shortened) : day
        let base = "\(when), \(RecorderModel.minutesText(info.duration))"
        if !info.hasAudio { return base + ", no audio" }
        // Step 9: a warning a few days before old audio goes.
        if let left = AudioCleanup.daysLeft(info), left <= 3 {
            return when + (left <= 1 ? ", audio deletes tomorrow" : ", audio deletes in \(left) days")
        }
        return base
    }
}

/// Always at the top of the sidebar, like "New chat" in Claude.
/// Opens the start screen (recording begins from its Start button, Ryan's
/// ask); while recording it jumps back to it.
struct NewRecordingButton: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        SidebarAction(
            title: model.isBusy ? (model.phase == .paused ? "Paused, go to it" : "Recording now") : "New recording",
            icon: model.isBusy ? "waveform" : "plus",
            shortcut: model.isBusy ? nil : "⌘N",
            help: model.isBusy ? "Go to the recording in progress" : "Open a new recording (⌘N)",
            bold: true
        ) {
            model.showNewRecording()
        }
    }
}

/// One line at the top of the sidebar: icon, words, shortcut. Shaded on hover.
struct SidebarAction: View {
    let title: String
    let icon: String
    var shortcut: String?
    var help: String
    var bold = false
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .fontWeight(bold ? .semibold : .regular)
                    .frame(width: 16)
                Text(title)
                    .fontWeight(bold || selected ? .medium : .regular)
                    .lineLimit(1)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.1) : hovering ? Color.primary.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// "Recently deleted 3" at the top of the sidebar (step 9). Hidden when empty.
struct RecentlyDeletedButton: View {
    @Environment(RecorderModel.self) private var model
    private var deleted: RecentlyDeleted { .shared }

    var body: some View {
        if !deleted.items.isEmpty {
            SidebarAction(
                title: "Recently deleted",
                icon: "trash",
                shortcut: "\(deleted.items.count)",
                help: "Deleted recordings stay here for \(RecentlyDeleted.keepDays) days",
                selected: model.showingDeleted
            ) {
                model.selection = nil
                model.showingDeleted = true
            }
        }
    }
}

/// What a dragged recording carries. Inside Verbatim: which recording, so it
/// can move between groups. Dropped in another app (Claude, Finder, Notes):
/// its transcript as a Markdown file, named like an export.
struct RecordingDrag: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .verbatimRecording)
        FileRepresentation(exportedContentType: .markdownText) { item in
            let url = try await MainActor.run { try item.writeTranscript() }
            return SentTransferredFile(url)
        }
    }

    /// Writes the transcript to a fresh temporary folder and returns the file.
    @MainActor
    private func writeTranscript() throws -> URL {
        let model = RecorderModel.shared
        guard let info = model.info(id) else { throw CocoaError(.fileNoSuchFile) }
        let lines = model.shownLines(id).map(\.line)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Verbatim drag \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = RecorderModel.freeName(for: info, format: .markdown, in: folder)
        let url = folder.appending(path: name)
        try RecorderModel.text(lines, info: info, markdown: true).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

extension UTType {
    /// Declared in Support/Info.plist (UTExportedTypeDeclarations).
    static let verbatimRecording = UTType(exportedAs: "com.rywnswn.verbatim.recording")
    static let markdownText = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}
