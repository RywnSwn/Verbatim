import FluidAudio
import Foundation
import Observation

/// Who is talking when (step 7). Runs NVIDIA's Sortformer (streaming, the
/// "balanced" v2.1 model, 6-bit so it's ~100 MB and light on memory) next to
/// Parakeet. It tells voices apart, up to 4 at a time, about 1.5 s behind the
/// audio. It doesn't know names: they show as "Speaker 1", "Speaker 2" (see Speakers).
/// The only other file that talks to FluidAudio. Loaded only while in use.
actor SpeakerEngine {
    static let sizeText = "about 100 MB"

    static var config: SortformerConfig {
        var c = SortformerConfig.balancedV2_1
        c.precision = .palettized
        return c
    }

    /// Kept next to Parakeet (Models/Live), so old cleanups never touch it.
    static var base: URL { ParakeetEngine.base }

    private var diarizer: SortformerDiarizer?
    private(set) var frames = VoiceFrames()

    var isLoaded: Bool { diarizer != nil }

    /// Downloads the model (picks up where it stopped), loads it once so macOS
    /// optimises it for this Mac, then frees the memory.
    static func downloadAndPrepare(progress: @escaping @Sendable (_ fraction: Double, _ preparing: Bool) -> Void) async throws {
        let models = try await SortformerModels.loadFromHuggingFace(config: config, cacheDirectory: base) { p in
            switch p.phase {
            case .compiling: progress(1, true)
            default: progress(p.fractionCompleted, false)
            }
        }
        progress(1, true)
        let d = SortformerDiarizer(config: config)
        d.initialize(models: models)
        d.cleanup()
    }

    /// Loads from disk. Only called once the model is downloaded, so it never
    /// needs the internet.
    func load() async throws {
        guard diarizer == nil else { return }
        let models = try await SortformerModels.loadFromHuggingFace(config: Self.config, cacheDirectory: Self.base)
        let d = SortformerDiarizer(config: Self.config)
        d.initialize(models: models)
        diarizer = d
    }

    func unload() {
        diarizer?.cleanup()
        diarizer = nil
        frames = VoiceFrames()
    }

    /// A new stretch of listening: voices are numbered afresh (0 to 3).
    /// Known voices (step 7c) are played to it first; returns which number
    /// each one got, so their lines get the name straight away.
    @discardableResult
    func begin(known: [KnownVoice] = []) async throws -> [Int: String] {
        try await load()
        diarizer?.reset()
        frames = VoiceFrames()
        var names: [Int: String] = [:]
        for voice in known {
            guard let diarizer else { break }
            if let speaker = try? diarizer.enrollSpeaker(withAudio: voice.samples, named: voice.name,
                                                        overwritingAssignedSpeakerName: false),
               names[speaker.index] == nil {
                names[speaker.index] = voice.name
            }
        }
        return names
    }

    /// 16 kHz mono samples, in order. Pauses don't need anything: it just
    /// carries on when audio comes again.
    func feed(_ samples: [Float]) {
        guard let diarizer, !samples.isEmpty else { return }
        do {
            try diarizer.addAudio(samples, sourceSampleRate: nil)
            if let update = try diarizer.process() { take(update.chunkResult) }
        } catch {
            // A failed bit only means no voices for that bit.
        }
    }

    /// No more audio: work out the last second too.
    func finish() {
        guard let diarizer else { return }
        if let update = try? diarizer.finalizeSession() { take(update.chunkResult) }
        frames.tentative = []
    }

    /// Voice numbers for words. `shift` turns the words' times into seconds
    /// since `begin()`; `base` is added to every voice (see LiveText.voiceSessions).
    func label(_ pieces: [LivePiece], shift: Double, base: Int) -> [LivePiece] {
        pieces.map { p in
            var p = p
            p.voice = frames.voice(p.start + shift, p.end + shift).map { $0 + base }
            return p
        }
    }

    private func take(_ chunk: DiarizerChunkResult) {
        let n = Self.config.numSpeakers
        frames.put(VoiceFrames.loudest(chunk.finalizedPredictions, speakers: n), at: chunk.startFrame)
        frames.tentative = VoiceFrames.loudest(chunk.tentativePredictions, speakers: n)
    }
}

/// For every 0.08 s of audio, which voice (0 to 3) was talking, or -1 for
/// nobody. `tentative` is the last second or so, which may still change.
struct VoiceFrames: Sendable {
    static let seconds = 0.08

    var final: [Int8] = []
    var tentative: [Int8] = []

    var count: Int { final.count + tentative.count }

    subscript(i: Int) -> Int8 { i < final.count ? final[i] : tentative[i - final.count] }

    mutating func put(_ new: [Int8], at start: Int) {
        guard !new.isEmpty else { return }
        if start > final.count { final += [Int8](repeating: -1, count: start - final.count) }
        let overlap = final.count - start
        if overlap > 0 { final.removeLast(overlap) }
        final += new
    }

    /// The loudest voice in each frame, if it's sure enough someone talks.
    static func loudest(_ probs: [Float], speakers n: Int) -> [Int8] {
        guard n > 0 else { return [] }
        return stride(from: 0, to: probs.count - probs.count % n, by: n).map { i in
            var best = -1
            var bestP: Float = 0.5
            for k in 0..<n where probs[i + k] > bestP {
                best = k
                bestP = probs[i + k]
            }
            return Int8(best)
        }
    }

    /// The voice heard most between two times (seconds since the start). If
    /// nobody was heard right there, the nearest voice within a second. If the
    /// time isn't reached yet (words can be ahead), the latest voice heard.
    func voice(_ start: Double, _ end: Double) -> Int? {
        let total = count
        guard total > 0 else { return nil }
        var a = max(0, Int(start / Self.seconds))
        var b = max(a + 1, Int((end / Self.seconds).rounded(.up)))
        if a >= total {
            a = max(0, total - 25)
            b = total
            for i in stride(from: total - 1, through: a, by: -1) where self[i] >= 0 { return Int(self[i]) }
            return nil
        }
        b = min(b, total)
        if let v = mostHeard(a, b) { return v }
        return mostHeard(max(0, a - 12), min(total, b + 12))
    }

    private func mostHeard(_ a: Int, _ b: Int) -> Int? {
        var votes = [Int](repeating: 0, count: 8)
        for i in a..<b {
            let v = Int(self[i])
            if v >= 0, v < votes.count { votes[v] += 1 }
        }
        guard let top = votes.indices.max(by: { votes[$0] < votes[$1] }), votes[top] > 0 else { return nil }
        return top
    }
}

/// The speaker model download, like Parakeet's (LiveTranscriber), but quieter:
/// it starts after Parakeet is ready, since live text matters more. Until it's
/// here, lines just have no speaker; they get one afterwards ("Find speakers").
@MainActor
@Observable
final class SpeakerModel {
    static let shared = SpeakerModel()

    enum State: Equatable {
        case waiting
        case downloading(fraction: Double)
        case failed(fraction: Double)
        case preparing
        case ready
    }

    private(set) var state: State = .waiting
    var isReady: Bool { state == .ready }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    private static let preparedKey = "speakerModelPrepared"

    private init() {
        if UserDefaults.standard.bool(forKey: Self.preparedKey) { state = .ready }
    }

    /// Called at launch and when Parakeet is ready. Waits for Parakeet first.
    func startIfNeeded() {
        guard state != .ready, state != .preparing, task == nil, LiveTranscriber.shared.isModelReady else { return }
        retryTask?.cancel()
        retryTask = nil
        state = .downloading(fraction: fraction)
        task = Task {
            do {
                try await SpeakerEngine.downloadAndPrepare { f, preparing in
                    Task { @MainActor in SpeakerModel.shared.progress(f, preparing: preparing) }
                }
                UserDefaults.standard.set(true, forKey: Self.preparedKey)
                task = nil
                state = .ready
                Transcriber.shared.speakerModelReady()
            } catch {
                task = nil
                state = .failed(fraction: fraction)
                retryTask = Task {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    startIfNeeded()
                }
            }
        }
    }

    /// The model on disk didn't load: get it again.
    func broken() {
        UserDefaults.standard.removeObject(forKey: Self.preparedKey)
        state = .failed(fraction: 0)
        startIfNeeded()
    }

    private var fraction: Double {
        switch state {
        case .downloading(let f), .failed(let f): f
        case .waiting: 0
        case .preparing, .ready: 1
        }
    }

    private func progress(_ f: Double, preparing: Bool) {
        guard task != nil, state != .ready else { return }
        state = preparing ? .preparing : .downloading(fraction: f)
    }
}
