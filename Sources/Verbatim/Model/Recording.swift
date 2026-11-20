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
    /// Full path of that file, only while its sound is being copied in. Still
    /// set at launch = Verbatim quit mid-import, so the copy starts over
    /// (UX round 2, A6).
    var importingPath: String?
    /// Where the last copy ended (seconds into the audio), for "Copy new since last copy".
    var copiedUpTo: Double?
    /// Set when Ryan deleted only the audio (right-click > Delete Audio Only).
    /// The transcript stays.
    var audioDeletedAt: Date?
    /// Moments Ryan marked with ⌘D (seconds into the audio), step 7b.
    var markers: [Double]?
    /// Notes Ryan typed on lines (see `Notes`).
    var notes: [LineNote]?
    /// Right-click > Keep Audio: old-audio cleanup skips it (step 9).
    var keepAudio: Bool?
    /// Sidebar group (step 10). nil = Recents.
    var groupID: UUID?
    /// An SF Symbol Ryan picked for this one recording (step 10).
    var icon: String?
    var iconColor: IconColor?
    /// The title was made by Verbatim ("Wed 12 Nov", a file name), not typed
    /// by Ryan, so auto-naming may replace it (step 10). Renaming clears it.
    var autoTitle: Bool?

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
    /// The 48 kHz copy for listening (since 2026-11-19), written while
    /// recording next to audio.wav. Never used to make text.
    static func listenWavURL(_ id: UUID) -> URL { folder(id).appending(path: "listen.wav") }
    /// The listening copy, shrunk gently after Stop (AAC 64 kbps).
    static func listenM4aURL(_ id: UUID) -> URL { folder(id).appending(path: "listen.m4a") }

    /// What the player plays: the 48 kHz copy if there is one, else the
    /// 16 kHz audio (imports and recordings from before).
    static func playbackURL(_ id: UUID) -> URL {
        for url in [listenM4aURL(id), listenWavURL(id)] where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return audioURL(id)
    }

    /// Every audio file the recording has (Delete Audio removes them all).
    static func audioFiles(_ id: UUID) -> [URL] {
        [wavURL(id), m4aURL(id), listenWavURL(id), listenM4aURL(id)]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func infoURL(_ id: UUID) -> URL { folder(id).appending(path: "recording.json") }

    /// When the recording's folder was made (when a file was imported).
    static func addedDate(_ id: UUID) -> Date? {
        (try? folder(id).resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    /// Size of the audio file in bytes, nil if it's gone.
    static func audioSize(_ id: UUID) -> Int64? {
        let files = audioFiles(id)
        guard !files.isEmpty else { return nil }
        return files.reduce(0) { sum, url in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return sum + ((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        }
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
