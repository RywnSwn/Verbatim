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
    func transcribe(_ samples: [Float]) async throws -> [Transcript.Line] {
        guard let pipe else { throw CocoaError(.featureUnsupported) }
        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .flatMap(\.segments)
            .map { Transcript.Line(start: Double($0.start), end: Double($0.end), text: Self.clean($0.text)) }
            .filter { !$0.text.isEmpty && !Self.isJunk($0.text) }
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
        let key = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return key.isEmpty || junk.contains(key)
    }
}
