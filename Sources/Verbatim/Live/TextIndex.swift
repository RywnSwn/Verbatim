import Foundation

/// The few things launch needs to know about a recording's text, without
/// reading the whole text (a long class is a few hundred KB of live.json).
/// The Transcriber uses them to pick up unfinished work and to find speakers.
struct TextFacts: Codable, Equatable {
    var hasLines = false
    /// Parakeet going over the file: nil = no file pass, else whether it finished.
    var passFinished: Bool?
    /// Ryan pressed Cancel on the file pass.
    var passStoppedByUser = false
    var speakersFound = false
    /// Some line already has a voice from the speaker model.
    var hasVoices = false
    /// Made (partly) with Apple's backup engine.
    var backupEngine = false

    init() {}

    init(_ t: LiveText?) {
        guard let t else { return }
        hasLines = !t.lines.isEmpty
        passFinished = t.pass?.finished
        passStoppedByUser = t.pass?.stoppedByUser ?? false
        speakersFound = t.speakersFound == true
        hasVoices = t.lines.contains { $0.voice != nil }
        backupEngine = t.madeWithBackupEngine
    }

    /// A file pass started and isn't finished.
    var passUnfinished: Bool { passFinished == false }
}

/// `TextFacts` for every recording, in one small file
/// (App Support/Verbatim/text-index.json), so launch reads one file instead of
/// every live.json. Each entry remembers the size and date of the live.json it
/// was made from. If the file changed since (a quit between the two saves, a
/// recording put back from Recently deleted, an older Verbatim), the entry
/// doesn't count and the text is read again in the background.
enum TextIndex {
    static let currentFormat = 1

    /// Size and modification date of a live.json.
    struct Stamp: Codable, Equatable {
        var size: Int64
        var modified: Double

        func matches(_ other: Stamp) -> Bool {
            size == other.size && abs(modified - other.modified) < 0.001
        }
    }

    struct Entry: Codable, Equatable {
        var facts: TextFacts
        var stamp: Stamp
    }

    private struct File: Codable {
        var formatVersion = TextIndex.currentFormat
        var entries: [String: Entry]
    }

    static var url: URL {
        RecordingStore.root.deletingLastPathComponent().appending(path: "text-index.json")
    }

    /// The live.json's size and date now. nil = there is no live.json.
    static func stamp(_ id: UUID) -> Stamp? {
        let values = try? LiveStore.url(id).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize, let date = values?.contentModificationDate else { return nil }
        return Stamp(size: Int64(size), modified: date.timeIntervalSinceReferenceDate)
    }

    static func load() -> [UUID: Entry] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.formatVersion == currentFormat else { return [:] }
        var out: [UUID: Entry] = [:]
        for (key, entry) in file.entries {
            if let id = UUID(uuidString: key) { out[id] = entry }
        }
        return out
    }

    static func save(_ entries: [UUID: Entry]) throws {
        var file = File(entries: [:])
        for (id, entry) in entries { file.entries[id.uuidString] = entry }
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
    }
}
