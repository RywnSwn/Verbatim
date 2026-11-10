import Foundation

/// The old Whisper transcript (transcript.json), from before step 5c. New
/// text lives in live.json only; old files still open and can be edited.
struct Transcript: Codable, Equatable {
    static let currentFormat = 1

    struct Line: Codable, Hashable {
        /// Seconds into the audio file.
        var start: Double
        var end: Double
        var text: String
        /// Ryan edited this line: later passes never change it. nil = not locked.
        var locked: Bool? = nil
        /// When each word starts (seconds into the audio), for the player's word
        /// highlight. Same count as the words in `text`; nil after an edit or in
        /// older files (the highlight then estimates).
        var words: [Double]? = nil

        var isLocked: Bool { locked == true }

        /// Middle of the line.
        var middle: Double { (start + end) / 2 }
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

    /// The quietest 0.1 s moment in the few seconds before `target`, so pieces
    /// are cut between words, not through them.
    static func quietPoint(_ url: URL, before target: Int64, searchSeconds: Int64 = 8) -> Int64 {
        quietest(url, from: max(0, target - searchSeconds * rate), to: target) ?? target
    }

    /// The middle of the quietest 0.1 s between `from` and `to` (samples).
    /// `to` if the stretch is too short to look at.
    static func quietPoint(_ url: URL, from: Int64, to: Int64) -> Int64 {
        quietest(url, from: from, to: to) ?? to
    }

    private static func quietest(_ url: URL, from: Int64, to: Int64) -> Int64? {
        let window: Int64 = 1_600
        guard to - from >= window, let samples = try? samples(url, from: from, count: to - from),
              samples.count >= Int(window) else { return nil }
        var best: Int64?
        var bestEnergy = Float.greatestFiniteMagnitude
        var i = 0
        while i + Int(window) <= samples.count {
            var energy: Float = 0
            for j in i..<(i + Int(window)) { energy += samples[j] * samples[j] }
            if energy < bestEnergy {
                bestEnergy = energy
                best = from + Int64(i) + window / 2
            }
            i += Int(window) / 4
        }
        return best
    }
}
