import Foundation

/// Parakeet's transcript of a whole file (imports, "Transcribe again", or a
/// recording whose live text came from Apple's backup engine), saved as
/// transcript.json next to audio.wav. Saved as it goes, so a crash or Cancel
/// keeps what was done. Older recordings may have one written by Whisper.
/// Recordings with Parakeet live text have none: live.json is their transcript.
struct Transcript: Codable, Equatable {
    static let currentFormat = 1

    struct Line: Codable, Hashable {
        /// Seconds into the audio file.
        var start: Double
        var end: Double
        var text: String
        /// Ryan edited this line: "Transcribe again" keeps it. nil = not locked.
        var locked: Bool? = nil

        var isLocked: Bool { locked == true }
    }

    var formatVersion = Transcript.currentFormat
    var model: String
    /// Everything before this point (seconds into the audio) has been transcribed.
    var doneUpTo: Double = 0
    var finished = false
    /// Ryan pressed Cancel: don't restart it by itself on next launch.
    var stoppedByUser = false
    var lines: [Line] = []

    var plainText: String { lines.map(\.text).joined(separator: "\n") }
}

enum TranscriptStore {
    static func url(_ id: UUID) -> URL {
        RecordingStore.folder(id).appending(path: "transcript.json")
    }

    static func load(_ id: UUID) -> Transcript? {
        guard let data = try? Data(contentsOf: url(id)) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    static func save(_ transcript: Transcript, for id: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(transcript).write(to: url(id), options: .atomic)
    }
}

/// Reads pieces of our 16 kHz mono WAV files as Float samples.
enum WavReader {
    static let rate: Int64 = 16_000

    static func sampleCount(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return max(0, (Int64(size) - Int64(WavWriter.headerSize)) / 2)
    }

    static func samples(_ url: URL, from start: Int64, count: Int64) throws -> [Float] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: WavWriter.headerSize + UInt64(start) * 2)
        let data = try handle.read(upToCount: Int(count) * 2) ?? Data()
        return data.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32_768 }
        }
    }
}

extension Transcript.Line {
    /// Middle of the line. Decides which side of a point in time a line is on.
    var middle: Double { (start + end) / 2 }
}

extension LiveText {
    /// Live lines a file transcription hasn't replaced yet.
    func unchecked(after doneUpTo: Double) -> [Transcript.Line] {
        lines.filter { $0.middle >= doneUpTo }
    }
}
