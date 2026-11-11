import AppKit
import SwiftUI

/// The main area when "Recently deleted" is picked in the sidebar (step 9).
struct RecentlyDeletedView: View {
    @Environment(RecorderModel.self) private var model
    private var deleted: RecentlyDeleted { .shared }
    @State private var confirmEmpty = false
    @State private var confirmDelete: RecentlyDeleted.Item?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently deleted")
                        .font(.system(size: 26, design: .serif))
                    Text("Deleted recordings stay here for \(RecentlyDeleted.keepDays) days, then they're gone for good.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !deleted.items.isEmpty {
                    Button("Empty…") { confirmEmpty = true }
                        .help("Delete everything here for good")
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 16)
            Divider()

            if deleted.items.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing here.")
                        .font(.title3)
                    Text("When you delete a recording, it waits here in case you change your mind.")
                        .foregroundStyle(.secondary)
                    Button("Back to recordings") { model.showingDeleted = false }
                        .buttonStyle(.link)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(deleted.items) { item in
                            row(item)
                            Divider()
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .alert("Delete everything in Recently deleted?", isPresented: $confirmEmpty) {
            Button("Delete \(deleted.items.count == 1 ? "It" : "All \(deleted.items.count)")", role: .destructive) {
                deleted.empty()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(Storage.text(deleted.totalSize)). It can't be undone.")
        }
        .alert("Delete \(confirmDelete?.info.title ?? "") for good?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let item = confirmDelete { deleted.deleteNow(item.id) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("The text and audio are gone for good. This can't be undone.")
        }
        .onAppear { deleted.load() }
    }

    private func row(_ item: RecentlyDeleted.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.info.title).font(.body.weight(.medium))
                Text(meta(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let preview = item.preview {
                    Text(preview)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Put Back") { model.putBack(item.id) }
                .help("Back in the sidebar, as it was")
            Button("Delete Now") { confirmDelete = item }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .contextMenu {
            Button("Put Back") { model.putBack(item.id) }
            Button("Delete Now…") { confirmDelete = item }
        }
    }

    private func meta(_ item: RecentlyDeleted.Item) -> String {
        let made = item.info.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let left = item.daysLeft == 1 ? "gone tomorrow" : "\(item.daysLeft) days left"
        return "\(made), \(RecorderModel.minutesText(item.info.duration)), \(Storage.text(item.size)), \(left)"
    }
}

/// Settings > Storage (step 9): how long audio is kept, what takes space,
/// Export Everything, Delete All.
struct StorageSettings: View {
    @Environment(RecorderModel.self) private var model
    @AppStorage(AudioCleanup.daysKey) private var keepDays = 7
    @State private var sizes: Sizes?
    @State private var confirmDeleteAll = false
    private var deleted: RecentlyDeleted { .shared }

    struct Sizes {
        var rows: [(id: UUID, bytes: Int64)]
        var recordings: Int64
        var models: Int64
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Picker("Keep audio for:", selection: $keepDays) {
                    ForEach(AudioCleanup.choices, id: \.self) { d in
                        Text(d == 0 ? "Forever" : "\(d) days").tag(d)
                    }
                }
                .fixedSize()
                Text("Text is kept forever. Audio is never deleted before its text is finished. To keep one recording's audio, right-click it in the sidebar > Keep Audio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Space used:") {
                    if let sizes {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Storage.text(sizes.recordings + sizes.models + deleted.totalSize)).font(.body.weight(.medium))
                            Text("Recordings \(Storage.text(sizes.recordings)), speech models \(Storage.text(sizes.models))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if deleted.totalSize > 0 {
                                Text("Recently deleted \(Storage.text(deleted.totalSize))")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Working it out…").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.columns)

            if let sizes, !sizes.rows.isEmpty {
                Text("Biggest recordings").font(.headline).padding(.top, 4)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(sizes.rows.prefix(30).enumerated()), id: \.element.id) { i, row in
                            if let info = model.info(row.id) {
                                biggest(info, bytes: row.bytes)
                                if i < min(sizes.rows.count, 30) - 1 { Divider() }
                            }
                        }
                    }
                }
                .frame(maxHeight: 170)
                .background(Theme.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider().padding(.vertical, 4)
            HStack {
                Button("Export Everything…") { model.exportEverything() }
                    .help("A zip with every transcript (as .md files you can read anywhere) and your settings. No audio.")
                Spacer()
                Button("Delete All Recordings…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(model.recordings.allSatisfy { !model.canDelete($0.id) })
            }
        }
        .padding(24)
        .task(id: model.recordings.map(\.hasAudio)) { await measure() }
        .alert("Delete all recordings?", isPresented: $confirmDeleteAll) {
            Button("Delete All", role: .destructive) { model.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They move to Recently deleted, where you can put them back for \(RecentlyDeleted.keepDays) days."
                 + (model.isBusy ? " The recording in progress stays." : ""))
        }
    }

    private func biggest(_ info: RecordingInfo, bytes: Int64) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                Text(info.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                     + (info.hasAudio ? "" : ", no audio"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Storage.text(bytes)).monospacedDigit().foregroundStyle(.secondary)
            let blocker = model.audioDeleteBlocker(info.id)
            Button("Delete Audio") {
                model.deleteAudio(info.id)
            }
            .disabled(blocker != nil)
            .help(blocker ?? "The text stays. Undo in the bottom bar of the main window.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func measure() async {
        let ids = model.recordings.map(\.id)
        let modelFolders = [ParakeetEngine.base, ParakeetEngine.wordSpotterFolder]
        let result = await Task.detached(priority: .utility) { () -> Sizes in
            let rows = ids.map { (id: $0, bytes: Storage.size(of: RecordingStore.folder($0))) }
            return Sizes(rows: rows.sorted { $0.bytes > $1.bytes },
                         recordings: rows.reduce(0) { $0 + $1.bytes },
                         models: modelFolders.reduce(0) { $0 + Storage.size(of: $1) })
        }.value
        sizes = result
    }
}
