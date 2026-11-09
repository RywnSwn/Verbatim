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
                                SidebarRow(info: info, isLive: info.id == model.currentID, phase: model.phase, elapsed: model.elapsed)
                                    .tag(info.id)
                                    .contextMenu {
                                        Button("Rename…") {
                                            newTitle = info.title
                                            renaming = info
                                        }
                                        Button("Show in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([RecordingStore.audioURL(info.id)])
                                        }
                                    }
                            }
                        }
                    }
                }
            }
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
    let phase: RecorderModel.Phase
    let elapsed: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(info.title)
                .font(.body.weight(.medium))
            Text(meta)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        if isLive {
            let len = RecorderModel.minutesText(elapsed)
            return phase == .paused ? "Paused, \(len)" : "Recording now, \(len)"
        }
        let day = info.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day), \(RecorderModel.minutesText(info.duration))"
    }
}
