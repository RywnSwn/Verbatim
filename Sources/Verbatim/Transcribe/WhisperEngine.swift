import Foundation
import WhisperKit

/// The only file that talks to WhisperKit. Runs off the main thread.
/// One model is loaded at a time and unloaded when the queue is empty (8 GB Mac).
actor WhisperEngine {
    /// Large v3 Turbo, compressed. Most accurate model that fits 8 GB comfortably.
    static let variant = "large-v3-v20240930_626MB"
    static let sizeText = "626 MB"

    private var pipe: WhisperKit?

    /// Downloads the model. Resumes from where it stopped if the internet drops.
    static func download(base: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await WhisperKit.download(variant: variant, downloadBase: base) { p in
            progress(p.fractionCompleted)
        }
    }

    var isLoaded: Bool { pipe != nil }

    func load(folder: URL, base: URL) async throws {
        guard pipe == nil else { return }
        let config = WhisperKitConfig(
            downloadBase: base,
            modelFolder: folder.path,
            tokenizerFolder: base,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        pipe = try await WhisperKit(config)
    }

    func unload() async {
        await pipe?.unloadModels()
        pipe = nil
    }

    /// Transcribes one piece of audio (16 kHz mono). Times are seconds into the piece.
    /// `prompt` is the text just before this piece: Whisper reads it as context,
    /// which helps with names and with carrying a sentence across the cut.
    func transcribe(_ samples: [Float], prompt: String? = nil) async throws -> [WhisperSegment] {
        guard let pipe else { throw CocoaError(.featureUnsupported) }
        var promptTokens: [Int]?
        if let prompt, !prompt.isEmpty, let tokenizer = pipe.tokenizer {
            let limit = tokenizer.specialTokens.specialTokenBegin
            let tokens = tokenizer.encode(text: " " + prompt).filter { $0 < limit }
            if !tokens.isEmpty { promptTokens = Array(tokens.suffix(Self.promptTokenLimit)) }
        }
        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: true,
            promptTokens: promptTokens,
            chunkingStrategy: .vad
        )
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let echo = prompt.map(Self.key) ?? ""
        return results
            .flatMap(\.segments)
            .compactMap { segment -> WhisperSegment? in
                let text = Self.clean(segment.text)
                guard !text.isEmpty, !Self.isJunk(text) else { return nil }
                // With a prompt, Whisper sometimes just repeats it on unclear audio.
                let k = Self.key(text)
                if k.count > 20, echo.contains(k) { return nil }
                let words = (segment.words ?? []).compactMap { w -> WhisperWord? in
                    let word = Self.cleanWord(w.word)
                    guard !word.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    return WhisperWord(text: word, start: Double(w.start), end: Double(w.end))
                }
                return WhisperSegment(start: Double(segment.start), end: Double(segment.end), text: text, words: words)
            }
    }

    /// Whisper allows up to 223 prompt tokens; a short one is safer (long
    /// prompts make it more likely to copy the prompt instead of listening).
    private static let promptTokenLimit = 120

    /// Removes special tokens but keeps the leading space that separates words.
    private static func cleanWord(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper invents these on silence or noise.
    private static let junk: Set<String> = [
        "thank you for watching", "thanks for watching", "thank you so much for watching",
        "please subscribe", "like and subscribe", "subtitles by the amaraorg community",
        "music", "blank_audio", "silence", "you", "bye", "applause", "inaudible",
    ]

    private static func isJunk(_ text: String) -> Bool {
        let k = key(text)
        return k.isEmpty || junk.contains(k)
    }

    /// Lowercase letters and spaces only, for comparing text.
    private static func key(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}

/// One stretch of Whisper text. Times are seconds into the piece of audio.
struct WhisperSegment: Sendable {
    var start: Double
    var end: Double
    var text: String
    /// Each word with its time. Words keep their leading space (" hello").
    /// Can be empty if Whisper couldn't time them.
    var words: [WhisperWord]
}

struct WhisperWord: Sendable {
    var text: String
    var start: Double
    var end: Double
}
