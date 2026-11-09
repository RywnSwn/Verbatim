@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// The only file that talks to FluidAudio. Runs NVIDIA's Parakeet Unified
/// 0.6B (English, punctuation, about 2 seconds behind speech) on the Neural
/// Engine. Loaded only while recording, unloaded after Stop (8 GB Mac).
actor ParakeetEngine: LiveEngine {
    static let name = "Parakeet"
    static let sizeText = "about 600 MB"

    /// ~/Library/Application Support/Verbatim/Models/Live, next to the Whisper model.
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
    }

    func begin() async throws {
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
        return LiveOutput(finals: words(from: await manager.consumeTokenTimings(), flush: false))
    }

    func end() async -> LiveOutput {
        guard let manager else { return LiveOutput() }
        _ = try? await manager.finish()
        let out = words(from: await manager.consumeTokenTimings(), flush: true)
        try? await manager.reset()
        return LiveOutput(finals: out)
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
