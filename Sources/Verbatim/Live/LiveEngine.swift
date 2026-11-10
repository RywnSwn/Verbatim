import Foundation

/// A few words of live text. Times are seconds since the engine's session began.
struct LivePiece: Sendable {
    var text: String
    var start: Double
    var end: Double
    /// Which voice said it (step 7). Set by SpeakerEngine, not by the engines.
    var voice: Int? = nil
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

/// The transcript of one recording, saved as live.json next to audio.wav.
/// Since step 5c this is THE transcript: written live while recording, or by
/// Parakeet going over the file (imports, Transcribe again).
struct LiveText: Codable, Equatable {
    static let currentFormat = 1
    var formatVersion = LiveText.currentFormat
    var lines: [Transcript.Line] = []
    /// Which engines wrote it, for comparing them later.
    var engines: [String] = []
    /// Lines Ryan deleted (seconds into audio.wav). nil in files from before editing.
    var removed: [Span]?
    /// Set when Parakeet goes over the audio file instead of listening live.
    /// nil = written live while recording.
    var pass: FilePass?
    /// Names Ryan gave a whole voice ("Change all"), by voice number as text:
    /// "#teacher", "#student" or a name.
    var voiceNames: [String: String]?
    /// How many times the speaker model started listening on this recording.
    /// Each time it numbers voices 0 to 3 again, so voice = time * 4 + number.
    var voiceSessions: Int?
    /// The speaker model went over the whole file ("Find speakers").
    var speakersFound: Bool?

    struct Span: Codable, Equatable {
        var start: Double
        var end: Double
    }

    struct FilePass: Codable, Equatable {
        /// Everything before this (seconds into audio.wav) is done.
        var doneUpTo: Double = 0
        var finished = false
        /// Ryan pressed Cancel: don't restart it by itself on next launch.
        var stoppedByUser = false
        /// Lines Ryan edited before "Transcribe again", still to be put back
        /// in place (as he wrote them) as the pass gets to them.
        var keep: [Transcript.Line]?
    }

    /// Lines after an old Whisper transcript's end (`doneUpTo`), by their middle.
    func unchecked(after doneUpTo: Double) -> [Transcript.Line] {
        doneUpTo <= 0 ? lines : lines.filter { $0.middle >= doneUpTo }
    }

    var madeWithBackupEngine: Bool { engines.contains(AppleSpeechEngine.name) }
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
        let starts = wordStarts(text, piece)
        if extendLast, let last = lines.last, !last.isLocked, !shouldBreak(after: last, before: piece, adding: text) {
            let i = lines.count - 1
            lines[i].text = last.text + " " + text
            lines[i].end = max(last.end, piece.end)
            lines[i].words = last.words.map { $0 + starts }
            if lines[i].voice == nil { lines[i].voice = piece.voice }
        } else {
            lines.append(Transcript.Line(start: piece.start, end: piece.end, text: text, words: starts, voice: piece.voice))
        }
    }

    /// Start time of each word in the piece. Parakeet gives one word per piece;
    /// Apple's engine gives phrases, spread evenly. Rounded to 0.01 s (smaller file).
    private static func wordStarts(_ text: String, _ piece: LivePiece) -> [Double] {
        let count = text.split(whereSeparator: \.isWhitespace).count
        guard count > 0 else { return [] }
        let step = count > 1 ? max(0, piece.end - piece.start) / Double(count) : 0
        return (0..<count).map { k in ((piece.start + Double(k) * step) * 100).rounded() / 100 }
    }

    private static func shouldBreak(after line: Transcript.Line, before piece: LivePiece, adding text: String) -> Bool {
        if piece.start - line.end > pauseGap { return true }
        // Someone else talks: new line, so each line has one speaker.
        if let a = line.voice, let b = piece.voice, a != b { return true }
        if line.text.count + text.count > hardMax { return true }
        if let c = line.text.last, ".?!".contains(c), line.text.count >= sentenceMin { return true }
        return false
    }
}
