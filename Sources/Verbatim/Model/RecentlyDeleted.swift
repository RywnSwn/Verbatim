import Foundation
import Observation

/// Step 9: deleted recordings wait in App Support/Verbatim/Deleted for 30
/// days (Put Back or Delete Now), then go for good. Like Notes' Recently Deleted.
@MainActor
@Observable
final class RecentlyDeleted {
    static let shared = RecentlyDeleted()
    static let keepDays = 30

    struct Item: Identifiable, Hashable {
        var info: RecordingInfo
        var deletedAt: Date
        var size: Int64
        /// First words of the transcript, so it's easy to tell recordings apart.
        var preview: String?
        var id: UUID { info.id }

        var daysLeft: Int {
            let end = deletedAt.addingTimeInterval(Double(RecentlyDeleted.keepDays) * 86_400)
            return max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
        }
    }

    private struct Note: Codable {
        var deletedAt: Date
    }

    private(set) var items: [Item] = []

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Verbatim/Deleted", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(_ id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    private init() { load() }

    /// Reads the folder, and removes anything older than 30 days.
    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        var list: [Item] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appending(path: "recording.json")),
                  let info = try? decoder.decode(RecordingInfo.self, from: data) else { continue }
            let note = (try? Data(contentsOf: folder.appending(path: "deleted.json")))
                .flatMap { try? decoder.decode(Note.self, from: $0) }
            let item = Item(info: info, deletedAt: note?.deletedAt ?? Date(), size: Storage.size(of: folder),
                            preview: Self.preview(folder))
            if item.daysLeft == 0 {
                try? FileManager.default.removeItem(at: folder)
            } else {
                list.append(item)
            }
        }
        items = list.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Moves a recording's folder in here. Returns where it went.
    func add(_ info: RecordingInfo) throws -> URL {
        let target = Self.folder(info.id)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: RecordingStore.folder(info.id), to: target)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let now = Date()
        try? encoder.encode(Note(deletedAt: now)).write(to: target.appending(path: "deleted.json"))
        items.insert(Item(info: info, deletedAt: now, size: Storage.size(of: target), preview: Self.preview(target)), at: 0)
        return target
    }

    /// Back to the sidebar.
    func restore(_ id: UUID) throws {
        let from = Self.folder(id)
        try? FileManager.default.removeItem(at: from.appending(path: "deleted.json"))
        try FileManager.default.moveItem(at: from, to: RecordingStore.folder(id))
        items.removeAll { $0.id == id }
    }

    func deleteNow(_ id: UUID) {
        try? FileManager.default.removeItem(at: Self.folder(id))
        items.removeAll { $0.id == id }
    }

    func empty() {
        for item in items { try? FileManager.default.removeItem(at: Self.folder(item.id)) }
        items = []
    }

    private static func preview(_ folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appending(path: "live.json")),
              let text = try? JSONDecoder().decode(LiveText.self, from: data) else { return nil }
        let words = text.lines.prefix(3).map(\.text).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        return words.count > 110 ? String(words.prefix(110)) + "…" : words
    }
}

/// Sizes on disk, for Settings > Storage.
enum Storage {
    static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        while let f = e?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
