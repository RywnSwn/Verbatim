import Foundation

/// A few words of live text. Times are seconds since the engine's session began.
struct LivePiece: Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// What an engine hands back after each bit of audio.
struct LiveOutput: Sendable {
    /// Text that won't change any more.
    var finals: [LivePiece] = []
    /// Words still being worked out (Apple's engine only). nil = leave as is.
    var volatile: String?
}

/// A live speech-to-text engine. Swappable: Parakeet is the main one, Apple's
/// built-in engine fills in while Parakeet downloads. Engines get 16 kHz mono
/// samples, the same audio that goes into the file.
protocol LiveEngine: Actor {
    /// Starts a new stretch of audio (recording start, or after Pause).
    func begin() async throws
    func feed(_ samples: [Float]) async -> LiveOutput
    /// The stretch ended: finish the last words.
    func end() async -> LiveOutput
}

/// The live text of one recording, saved as live.json next to audio.wav.
struct LiveText: Codable, Equatable {
    static let currentFormat = 1
    var formatVersion = LiveText.currentFormat
    var lines: [Transcript.Line] = []
    /// Which engines wrote it, for comparing them later.
    var engines: [String] = []
    /// Lines Ryan deleted (seconds into audio.wav), so the accurate pass in
    /// step 5 doesn't bring them back. nil in files from before editing.
    var removed: [Span]?

    struct Span: Codable, Equatable {
        var start: Double
        var end: Double
    }
}

enum LiveStore {
    static func url(_ id: UUID) -> URL {
        RecordingStore.folder(id).appending(path: "live.json")
    }

    static func load(_ id: UUID) -> LiveText? {
        guard let data = try? Data(contentsOf: url(id)) else { return nil }
        return try? JSONDecoder().decode(LiveText.self, from: data)
    }

    static func save(_ live: LiveText, for id: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(live).write(to: url(id), options: .atomic)
    }
}

/// Turns a stream of words into readable lines: a new line after a sentence
/// ends (once the line has some length), after a pause, or when a line gets long.
enum LineBuilder {
    static let pauseGap = 1.6
    static let sentenceMin = 70
    static let hardMax = 260

    /// `extendLast` is false while the last line is being edited or was edited:
    /// new words then start a new line instead of changing Ryan's text.
    static func add(_ piece: LivePiece, to lines: inout [Transcript.Line], extendLast: Bool = true) {
        let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if extendLast, let last = lines.last, !last.isLocked, !shouldBreak(after: last, before: piece, adding: text) {
            lines[lines.count - 1].text = last.text + " " + text
            lines[lines.count - 1].end = max(last.end, piece.end)
        } else {
            lines.append(Transcript.Line(start: piece.start, end: piece.end, text: text))
        }
    }

    private static func shouldBreak(after line: Transcript.Line, before piece: LivePiece, adding text: String) -> Bool {
        if piece.start - line.end > pauseGap { return true }
        if line.text.count + text.count > hardMax { return true }
        if let c = line.text.last, ".?!".contains(c), line.text.count >= sentenceMin { return true }
        return false
    }
}
