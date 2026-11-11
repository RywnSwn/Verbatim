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
    /// File name of the Voice Memo (or other file) this was imported from.
    var importedFrom: String?
    /// Where the last copy ended (seconds into the audio), for "Copy new since last copy".
    var copiedUpTo: Double?
    /// Set when Ryan deleted only the audio (right-click > Delete Audio Only).
    /// The transcript stays.
    var audioDeletedAt: Date?
    /// Moments Ryan marked with ⌘D (seconds into the audio), step 7b.
    var markers: [Double]?
    /// Right-click > Keep Audio: old-audio cleanup skips it (step 9).
    var keepAudio: Bool?

    var duration: TimeInterval { Double(samples) / Double(sampleRate) }
    var isActive: Bool { state != .stopped }
    var hasAudio: Bool { audioDeletedAt == nil }

    /// Clock time for a point in the audio, skipping over pauses and sleep.
    func wallTime(atSecond seconds: Double) -> Date {
        let sample = Int64(seconds * Double(sampleRate))
        let starts: Set<Event.Kind> = [.started, .resumed, .woke, .undoStop, .micChanged]
        let anchor = events.last { starts.contains($0.kind) && $0.sample <= sample }
        guard let anchor else { return createdAt.addingTimeInterval(seconds) }
        return anchor.at.addingTimeInterval(Double(sample - anchor.sample) / Double(sampleRate))
    }
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

    /// The full-size file written while recording (crash safe).
    static func wavURL(_ id: UUID) -> URL { folder(id).appending(path: "audio.wav") }
    /// The squashed copy made after Stop (AAC, about 8 times smaller).
    static func m4aURL(_ id: UUID) -> URL { folder(id).appending(path: "audio.m4a") }

    /// The recording's audio: the squashed file once it exists, else the WAV.
    static func audioURL(_ id: UUID) -> URL {
        let m4a = m4aURL(id)
        return FileManager.default.fileExists(atPath: m4a.path) ? m4a : wavURL(id)
    }
    static func infoURL(_ id: UUID) -> URL { folder(id).appending(path: "recording.json") }

    /// When the recording's folder was made (when a file was imported).
    static func addedDate(_ id: UUID) -> Date? {
        (try? folder(id).resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    /// Size of the audio file in bytes, nil if it's gone.
    static func audioSize(_ id: UUID) -> Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL(id).path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

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
