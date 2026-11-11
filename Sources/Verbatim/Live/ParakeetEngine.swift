@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// The only file that talks to FluidAudio. Runs NVIDIA's Parakeet Unified
/// 0.6B (English, punctuation, about 2 seconds behind speech) on the Neural
/// Engine. Live text while recording, and files (Transcriber) at full speed.
/// Loaded only while in use (8 GB Mac).
actor ParakeetEngine: LiveEngine {
    static let name = "Parakeet"
    static let sizeText = "about 600 MB"

    /// ~/Library/Application Support/Verbatim/Models/Live.
    static var base: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appending(path: "Verbatim/Models/Live", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var folder: URL {
        base.appending(path: Repo.parakeetUnified.folderName, directoryHint: .isDirectory)
    }

    private var manager: StreamingUnifiedAsrManager?
    /// The word spotter (step 8), loaded next to Parakeet while the word list has words.
    private var spotter: CtcModels?
    /// The words Parakeet is listening for right now.
    private var boosted: [String] = []
    /// A word whose last piece may still be coming.
    private var pending: LivePiece?
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    var isLoaded: Bool { manager != nil }

    /// Downloads the model (picks up where it stopped if the internet drops), then
    /// loads it once so macOS optimises it for this Mac, then frees the memory.
    static func downloadAndPrepare(progress: @escaping @Sendable (_ fraction: Double, _ preparing: Bool) -> Void) async throws {
        let m = StreamingUnifiedAsrManager()
        try await m.loadModels(to: base, configuration: nil) { p in
            switch p.phase {
            case .compiling: progress(1, true)
            default: progress(p.fractionCompleted, false)
            }
        }
        progress(1, true)
        await m.cleanup()
    }

    // MARK: - Word spotter (step 8)

    static let wordSpotterSizeText = "about 100 MB"

    /// FluidAudio always reads the spotter's tokenizer from its own folder
    /// (App Support/FluidAudio/Models/parakeet-ctc-110m-coreml), so it lives there.
    static var wordSpotterFolder: URL { CtcModels.defaultCacheDirectory(for: .ctc110m) }

    static var wordSpotterOnDisk: Bool {
        CtcModels.modelsExist(at: wordSpotterFolder)
            && FileManager.default.fileExists(atPath: wordSpotterFolder.appending(path: "tokenizer.json").path)
    }

    /// Downloads the word spotter (picks up where it stopped), loads it once so
    /// macOS optimises it for this Mac, then frees the memory.
    static func downloadWordSpotter(progress: @escaping @Sendable (_ fraction: Double, _ preparing: Bool) -> Void) async throws {
        _ = try await ModelHub.loadModels(
            .parakeetCtc110m,
            modelNames: [ModelNames.CTC.melSpectrogramPath, ModelNames.CTC.audioEncoderPath],
            directory: wordSpotterFolder.deletingLastPathComponent(),
            computeUnits: CtcModels.defaultConfiguration().computeUnits
        ) { p in
            switch p.phase {
            case .compiling: progress(1, true)
            default: progress(p.fractionCompleted, false)
            }
        }
        progress(1, true)
        guard wordSpotterOnDisk else { throw CocoaError(.fileNoSuchFile) }
    }

    /// Parakeet listens for these words from now on. An empty list loads
    /// Parakeet fresh, since FluidAudio can't switch boosting off. Never throws:
    /// without the spotter, text still comes, just without the boost.
    private func listen(for terms: [String]) async {
        guard terms != boosted else { return }
        if terms.isEmpty {
            await unload()
            try? await load()
            return
        }
        do {
            if spotter == nil { spotter = try await CtcModels.load(from: Self.wordSpotterFolder) }
            guard let manager, let spotter else { return }
            let vocabulary = CustomVocabularyContext(terms: terms.map { CustomVocabularyTerm(text: $0) })
            try await manager.configureVocabularyBoosting(vocabulary: vocabulary, ctcModels: spotter)
            boosted = terms
        } catch {
            spotter = nil
            boosted = []
            await MainActor.run { WordModel.shared.broken() }
        }
    }

    /// Name fixes the spotter made since last time ("group bonds" to "Nyankupon").
    private func spotted(_ manager: StreamingUnifiedAsrManager) async -> [PhraseFix] {
        guard !boosted.isEmpty else { return [] }
        return await manager.consumeVocabularyReplacements().compactMap { r in
            guard r.shouldReplace, let to = r.replacementWord, !to.isEmpty else { return nil }
            return PhraseFix(from: r.originalWord, to: to)
        }
    }

    /// Loads from disk only, never the internet.
    func load() async throws {
        guard manager == nil else { return }
        let m = StreamingUnifiedAsrManager()
        try await m.loadModels(from: Self.folder)
        manager = m
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
        pending = nil
        spotter = nil
        boosted = []
    }

    func begin() async throws {
        try await load()
        await listen(for: await MainActor.run { WordList.shared.boostTerms })
        try await load()
        try await manager?.reset()
        pending = nil
    }

    func feed(_ samples: [Float]) async -> LiveOutput {
        guard let manager, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return LiveOutput() }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        do {
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
        } catch {
            return LiveOutput()
        }
        let finals = words(from: await manager.consumeTokenTimings(), flush: false)
        return LiveOutput(finals: finals, fixes: await spotted(manager))
    }

    func end() async -> LiveOutput {
        guard let manager else { return LiveOutput() }
        _ = try? await manager.finish()
        let out = words(from: await manager.consumeTokenTimings(), flush: true)
        let fixes = await spotted(manager)
        try? await manager.reset()
        return LiveOutput(finals: out, fixes: fixes)
    }

    /// Sub-word tokens become whole words. A token starting with a space starts a
    /// new word, so the word before it is done.
    private func words(from tokens: [TokenTiming], flush: Bool) -> [LivePiece] {
        var done: [LivePiece] = []
        for t in tokens {
            if t.token.hasPrefix(" ") || pending == nil {
                if let p = pending { done.append(p) }
                pending = LivePiece(text: t.token, start: t.startTime, end: t.endTime)
            } else {
                pending?.text += t.token
                pending?.end = t.endTime
            }
        }
        if flush, let p = pending {
            done.append(p)
            pending = nil
        }
        return done
    }
}
