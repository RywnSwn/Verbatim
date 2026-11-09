import Foundation

/// One recording's info, saved as recording.json next to audio.wav.
struct RecordingInfo: Codable, Identifiable, Hashable {
    static let currentFormat = 1

    enum State: String, Codable { case recording, paused, stopped }

    struct Event: Codable, Hashable {
        enum Kind: String, Codable {
            case started, paused, resumed, asleep, woke, micChanged, stopped, undoStop, recovered
        }
        var kind: Kind
        var at: Date
        /// Position in the audio file when it happened.
        var sample: Int64
        var note: String?
    }

    var formatVersion = RecordingInfo.currentFormat
    var id: UUID
    var title: String
    var createdAt: Date
    var endedAt: Date?
    var state: State
    var sampleRate = 16_000
    var samples: Int64 = 0
    var events: [Event] = []

    var duration: TimeInterval { Double(samples) / Double(sampleRate) }
    var isActive: Bool { state != .stopped }
}

/// Files live in ~/Library/Application Support/Verbatim/Recordings/<id>/.
enum RecordingStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Verbatim/Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(_ id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    static func audioURL(_ id: UUID) -> URL { folder(id).appending(path: "audio.wav") }
    static func infoURL(_ id: UUID) -> URL { folder(id).appending(path: "recording.json") }

    static func create(_ info: RecordingInfo) throws {
        try FileManager.default.createDirectory(at: folder(info.id), withIntermediateDirectories: true)
        try save(info)
    }

    static func save(_ info: RecordingInfo) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: infoURL(info.id), options: .atomic)
    }

    static func loadAll() -> [RecordingInfo] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appending(path: "recording.json")) else { return nil }
                return try? decoder.decode(RecordingInfo.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Bytes free on the disk that holds the recordings.
    static func freeSpace() -> Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
