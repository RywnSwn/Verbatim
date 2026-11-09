import Foundation
import Observation

/// Audio for the live engine: samples as they are saved, and a marker when the
/// mic stops (Pause, sleep) so the last words get finished.
enum LiveInput: Sendable {
    case samples([Float])
    case flush
}

/// Hands samples from the audio thread to the live engine, in order.
final class LiveFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<LiveInput>.Continuation?

    func open() -> AsyncStream<LiveInput> {
        let (stream, c) = AsyncStream<LiveInput>.makeStream()
        lock.withLock {
            continuation?.finish()
            continuation = c
        }
        return stream
    }

    var isOpen: Bool { lock.withLock { continuation != nil } }

    func yield(_ input: LiveInput) {
        lock.withLock { _ = continuation?.yield(input) }
    }

    func close() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }
}

/// Live text while recording: the Parakeet download, which engine is listening,
/// and the lines so far (saved to live.json as it goes).
@MainActor
@Observable
final class LiveTranscriber {
    static let shared = LiveTranscriber()

    enum ModelState: Equatable {
        case downloading(fraction: Double, secondsLeft: Double?)
        case paused(fraction: Double)
        case failed(fraction: Double)
        case preparing
        case ready
    }

    /// What the live engine is doing for the recording in progress.
    enum Status: Equatable {
        case starting
        case listening(engine: String)
        case off(reason: String)
    }

    private(set) var modelState: ModelState = .downloading(fraction: 0, secondsLeft: nil)
    private(set) var status: Status?
    private(set) var texts: [UUID: LiveText] = [:]
    /// Words Apple's engine is still working out. Shown after the last line.
    private(set) var volatile = ""
    private(set) var activeID: UUID?

    /// Written to from the audio thread.
    nonisolated let feed = LiveFeed()

    @ObservationIgnored private let runner = LiveRunner()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var progressSamples: [(Date, Double)] = []
    @ObservationIgnored private var lastSave = Date.distantPast
    /// Counts recording starts, so a finishing earlier run (before Undo Stop)
    /// can't clear the status of the new one.
    @ObservationIgnored private var generation = 0

    private static let preparedKey = "liveModelPrepared"

    var isModelReady: Bool { modelState == .ready }

    private init() {}

    /// Called once at launch with the saved recordings.
    func start(with recordings: [RecordingInfo]) {
        for r in recordings {
            if let t = LiveStore.load(r.id) { texts[r.id] = t }
        }
        if UserDefaults.standard.bool(forKey: Self.preparedKey) {
            modelState = .ready
        } else {
            startDownload()
            // Until Parakeet is here, Apple's engine fills in. Get its model now,
            // while there is internet, so it works in class.
            Task.detached(priority: .utility) {
                if await AppleSpeechEngine.readiness() == .needsDownload {
                    try? await AppleSpeechEngine.install()
                }
            }
        }
    }

    // MARK: - Recording

    /// Recording started (or Undo Stop). `samples` = audio already in the file.
    func recordingStarted(_ id: UUID, samples: Int64) {
        activeID = id
        volatile = ""
        status = .starting
        if texts[id] == nil { texts[id] = LiveText() }
        generation += 1
        let run = generation
        let stream = feed.open()
        let previous = runTask
        let runner = runner
        runTask = Task {
            await previous?.value
            await runner.run(id: id, run: run, stream: stream, position: samples)
        }
    }

    /// The mic stopped (Pause or sleep): finish the last words.
    func micStopped() {
        feed.yield(.flush)
    }

    func recordingStopped() {
        feed.close()
    }

    func lines(_ id: UUID) -> [Transcript.Line] { texts[id]?.lines ?? [] }

    func forget(_ id: UUID) { texts[id] = nil }

    func reload(_ id: UUID) { texts[id] = LiveStore.load(id) }

    // MARK: - From the runner

    fileprivate func setStatus(_ s: Status?, run: Int) {
        guard run == generation else { return }
        status = s
    }

    fileprivate func apply(_ out: LiveOutput, offset: Double, engine: String, to id: UUID, run: Int) {
        guard var t = texts[id] else { return }
        for p in out.finals {
            LineBuilder.add(LivePiece(text: p.text, start: p.start + offset, end: p.end + offset), to: &t.lines)
        }
        if !out.finals.isEmpty, t.engines.last != engine { t.engines.append(engine) }
        texts[id] = t
        if run == generation, let v = out.volatile { volatile = v }
        if Date().timeIntervalSince(lastSave) > 10 { save(id) }
    }

    fileprivate func save(_ id: UUID) {
        guard let t = texts[id], !t.lines.isEmpty else { return }
        try? LiveStore.save(t, for: id)
        lastSave = Date()
    }

    fileprivate func finished(_ id: UUID, run: Int) {
        save(id)
        guard run == generation else { return }
        activeID = nil
        status = nil
        volatile = ""
    }

    // MARK: - Parakeet download

    func startDownload() {
        guard downloadTask == nil, modelState != .ready, modelState != .preparing else { return }
        retryTask?.cancel()
        retryTask = nil
        progressSamples = []
        modelState = .downloading(fraction: currentFraction, secondsLeft: nil)
        downloadTask = Task {
            do {
                try await ParakeetEngine.downloadAndPrepare { fraction, preparing in
                    Task { @MainActor in LiveTranscriber.shared.downloadProgress(fraction, preparing: preparing) }
                }
                UserDefaults.standard.set(true, forKey: Self.preparedKey)
                downloadTask = nil
                modelState = .ready
            } catch {
                downloadTask = nil
                if case .paused = modelState { return }
                modelState = .failed(fraction: currentFraction)
                scheduleRetry()
            }
        }
    }

    func pauseDownload() {
        guard case .downloading(let fraction, _) = modelState else { return }
        modelState = .paused(fraction: fraction)
        downloadTask?.cancel()
        downloadTask = nil
    }

    /// The model on disk didn't load (deleted or broken): get it again.
    fileprivate func modelBroken() {
        UserDefaults.standard.removeObject(forKey: Self.preparedKey)
        modelState = .failed(fraction: 0)
        startDownload()
    }

    private var currentFraction: Double {
        switch modelState {
        case .downloading(let f, _), .paused(let f), .failed(let f): f
        case .preparing, .ready: 1
        }
    }

    private func downloadProgress(_ fraction: Double, preparing: Bool) {
        guard downloadTask != nil, modelState != .ready else { return }
        if preparing {
            modelState = .preparing
            return
        }
        guard case .downloading = modelState else { return }
        let now = Date()
        progressSamples.append((now, fraction))
        progressSamples.removeAll { now.timeIntervalSince($0.0) > 30 }
        var left: Double?
        if let first = progressSamples.first, now.timeIntervalSince(first.0) > 3, fraction > first.1 {
            left = (1 - fraction) / ((fraction - first.1) / now.timeIntervalSince(first.0))
        }
        modelState = .downloading(fraction: fraction, secondsLeft: left)
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, case .failed = modelState else { return }
            startDownload()
        }
    }
}

/// Runs off the main thread: feeds audio to an engine, one recording at a time.
actor LiveRunner {
    private let parakeet = ParakeetEngine()
    private let apple = AppleSpeechEngine()

    func run(id: UUID, run: Int, stream: AsyncStream<LiveInput>, position start: Int64) async {
        var position = start
        var engine: (any LiveEngine)?
        var name = ""
        var offset = 0.0
        var nextTry: Int64 = 0

        for await input in stream {
            switch input {
            case .samples(let samples):
                if engine == nil, position >= nextTry {
                    (engine, name) = await pick(run: run)
                    offset = Double(position) / 16_000
                    // Nothing could listen: look again after 15 s of audio.
                    if engine == nil { nextTry = position + 15 * 16_000 }
                }
                if let engine {
                    let out = await engine.feed(samples)
                    await deliver(out, offset: offset, engine: name, id: id, run: run)
                }
                position += Int64(samples.count)
            case .flush:
                if let e = engine {
                    let out = await e.end()
                    await deliver(out, offset: offset, engine: name, id: id, run: run)
                }
                engine = nil
                nextTry = 0
                await MainActor.run { LiveTranscriber.shared.save(id) }
            }
        }

        if let engine {
            await deliver(await engine.end(), offset: offset, engine: name, id: id, run: run)
        }
        await parakeet.unload() // free the memory for the accurate pass
        await MainActor.run { LiveTranscriber.shared.finished(id, run: run) }
    }

    private func deliver(_ out: LiveOutput, offset: Double, engine: String, id: UUID, run: Int) async {
        guard !out.finals.isEmpty || out.volatile != nil else { return }
        await MainActor.run { LiveTranscriber.shared.apply(out, offset: offset, engine: engine, to: id, run: run) }
    }

    /// Parakeet if it's downloaded, otherwise Apple's engine, otherwise nothing.
    private func pick(run: Int) async -> ((any LiveEngine)?, String) {
        let modelState = await MainActor.run { LiveTranscriber.shared.modelState }
        if modelState == .ready {
            await setStatus(.starting, run)
            do {
                try await parakeet.begin()
                await setStatus(.listening(engine: ParakeetEngine.name), run)
                return (parakeet, ParakeetEngine.name)
            } catch {
                await parakeet.unload()
                await MainActor.run { LiveTranscriber.shared.modelBroken() }
            }
        }

        switch await AppleSpeechEngine.readiness() {
        case .ready:
            guard await AppleSpeechEngine.authorize() else {
                await setStatus(.off(reason: "Speech Recognition is turned off for Verbatim in System Settings"), run)
                return (nil, "")
            }
            do {
                try await apple.begin()
                await setStatus(.listening(engine: AppleSpeechEngine.name), run)
                return (apple, AppleSpeechEngine.name)
            } catch {
                await setStatus(.off(reason: "the live model is still downloading"), run)
            }
        case .needsDownload:
            Task.detached(priority: .utility) { try? await AppleSpeechEngine.install() }
            await setStatus(.off(reason: "the live model is still downloading"), run)
        case .unavailable:
            await setStatus(.off(reason: "the live model is still downloading"), run)
        }
        return (nil, "")
    }

    private func setStatus(_ s: LiveTranscriber.Status, _ run: Int) async {
        await MainActor.run { LiveTranscriber.shared.setStatus(s, run: run) }
    }
}
