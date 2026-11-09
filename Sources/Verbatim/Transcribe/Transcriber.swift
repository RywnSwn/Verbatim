import Foundation
import Observation

/// Model download plus a queue of recordings to transcribe, one at a time.
@MainActor
@Observable
final class Transcriber {
    static let shared = Transcriber()

    enum ModelState: Equatable {
        case downloading(fraction: Double, secondsLeft: Double?)
        case paused(fraction: Double)
        case failed(fraction: Double)
        case preparing
        case ready
    }

    struct Job: Equatable {
        var id: UUID
        var doneSeconds: Double
        var totalSeconds: Double
        var secondsLeft: Double?
    }

    static let pieceSeconds: Int64 = 120

    private(set) var modelState: ModelState = .downloading(fraction: 0, secondsLeft: nil)
    private(set) var queue: [UUID] = []
    private(set) var active: Job?
    private(set) var importing: Set<UUID> = []
    private(set) var transcripts: [UUID: Transcript] = [:]
    private(set) var errors: [UUID: String] = [:]

    @ObservationIgnored private let engine = WhisperEngine()
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested: Set<UUID> = []
    @ObservationIgnored private var progressSamples: [(Date, Double)] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private static let folderKey = "modelFolder"
    private static let preparedKey = "modelPrepared"

    static var modelBase: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Verbatim/Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var modelFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.folderKey),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    var isModelReady: Bool { modelState == .ready }

    private init() {}

    /// Called once at launch with the saved recordings.
    func start(with recordings: [RecordingInfo]) {
        for r in recordings {
            if let t = TranscriptStore.load(r.id) { transcripts[r.id] = t }
        }
        // Pick up anything left unfinished (app quit, crash, or recorded before step 3).
        for r in recordings.reversed() where !r.isActive {
            let t = transcripts[r.id]
            if t == nil || (t?.finished == false && t?.stoppedByUser == false) { queue.append(r.id) }
        }
        if modelFolder != nil, UserDefaults.standard.bool(forKey: Self.preparedKey) {
            modelState = .ready
            runQueue()
        } else if modelFolder != nil {
            prepare()
        } else {
            startDownload()
        }
    }

    // MARK: - Model download

    func startDownload() {
        guard downloadTask == nil, modelState != .ready, modelState != .preparing else { return }
        retryTask?.cancel()
        retryTask = nil
        progressSamples = []
        let startFraction = currentFraction
        modelState = .downloading(fraction: startFraction, secondsLeft: nil)
        downloadTask = Task {
            do {
                let folder = try await WhisperEngine.download(base: Self.modelBase) { fraction in
                    Task { @MainActor in Transcriber.shared.downloadProgress(fraction) }
                }
                UserDefaults.standard.set(folder.path, forKey: Self.folderKey)
                downloadTask = nil
                prepare()
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

    private var currentFraction: Double {
        switch modelState {
        case .downloading(let f, _), .paused(let f), .failed(let f): f
        case .preparing, .ready: 1
        }
    }

    private func downloadProgress(_ fraction: Double) {
        guard case .downloading = modelState else { return }
        let now = Date()
        progressSamples.append((now, fraction))
        progressSamples.removeAll { now.timeIntervalSince($0.0) > 30 }
        var left: Double?
        if let first = progressSamples.first, now.timeIntervalSince(first.0) > 3, fraction > first.1 {
            let rate = (fraction - first.1) / now.timeIntervalSince(first.0)
            left = (1 - fraction) / rate
        }
        modelState = .downloading(fraction: fraction, secondsLeft: left)
    }

    /// Internet dropped: try again by itself. The download picks up where it stopped.
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, case .failed = modelState else { return }
            startDownload()
        }
    }

    /// First load after download: fetches the small tokenizer while online and lets
    /// macOS optimise the model for this Mac. Slow once, fast after.
    private func prepare() {
        guard let folder = modelFolder else { startDownload(); return }
        modelState = .preparing
        Task {
            do {
                try await engine.load(folder: folder, base: Self.modelBase)
                UserDefaults.standard.set(true, forKey: Self.preparedKey)
                modelState = .ready
                runQueue()
            } catch {
                await engine.unload()
                // A broken download: start it again (finished files are kept).
                UserDefaults.standard.removeObject(forKey: Self.folderKey)
                modelState = .failed(fraction: 0.99)
                scheduleRetry()
            }
        }
    }

    // MARK: - Queue

    func enqueue(_ id: UUID) {
        errors[id] = nil
        if var t = transcripts[id], t.stoppedByUser {
            t.stoppedByUser = false
            transcripts[id] = t
        }
        guard !queue.contains(id) else { return }
        queue.append(id)
        runQueue()
    }

    /// Throws away the transcript and does it again.
    func redo(_ id: UUID) {
        guard active?.id != id else { return }
        transcripts[id] = nil
        try? FileManager.default.removeItem(at: TranscriptStore.url(id))
        enqueue(id)
    }

    func cancel(_ id: UUID) {
        if active?.id == id { cancelRequested.insert(id) }
        queue.removeAll { $0 == id }
        if var t = transcripts[id], !t.finished {
            t.stoppedByUser = true
            transcripts[id] = t
            try? TranscriptStore.save(t, for: id)
        }
    }

    /// The recording was moved to the Trash.
    func forget(_ id: UUID) {
        if active?.id == id { cancelRequested.insert(id) }
        queue.removeAll { $0 == id }
        transcripts[id] = nil
        errors[id] = nil
    }

    func reload(_ id: UUID) {
        transcripts[id] = TranscriptStore.load(id)
    }

    func setImporting(_ id: UUID, _ on: Bool) {
        if on { importing.insert(id) } else { importing.remove(id) }
    }

    func isQueued(_ id: UUID) -> Bool { queue.contains(id) }

    private func runQueue() {
        guard workTask == nil, modelState == .ready, !queue.isEmpty else { return }
        workTask = Task {
            while let id = queue.first {
                await transcribe(id)
                if queue.first == id { queue.removeFirst() }
            }
            await engine.unload() // free the memory until the next recording
            workTask = nil
            runQueue()
        }
    }

    private func transcribe(_ id: UUID) async {
        let audio = RecordingStore.audioURL(id)
        guard FileManager.default.fileExists(atPath: audio.path) else { return }
        var t = transcripts[id] ?? Transcript(model: WhisperEngine.variant)
        guard !t.finished else { return }
        cancelRequested.remove(id)

        let total = WavReader.sampleCount(audio)
        var pos = min(Int64(t.doneUpTo * Double(WavReader.rate)), total)
        let rate = Double(WavReader.rate)
        active = Job(id: id, doneSeconds: Double(pos) / rate, totalSeconds: Double(total) / rate)

        guard let folder = modelFolder else { active = nil; return }
        do {
            try await engine.load(folder: folder, base: Self.modelBase)
        } catch {
            errors[id] = "Couldn't load the model: \(error.localizedDescription)"
            active = nil
            return
        }

        let started = Date()
        let startPos = pos
        while pos < total {
            if cancelRequested.contains(id) { break }
            var end = min(pos + Self.pieceSeconds * WavReader.rate, total)
            if end < total { end = WavReader.quietPoint(audio, before: end) }
            if end <= pos { end = min(pos + Self.pieceSeconds * WavReader.rate, total) }

            if end - pos >= WavReader.rate / 2 { // skip a final crumb under half a second
                do {
                    let samples = try WavReader.samples(audio, from: pos, count: end - pos)
                    let offset = Double(pos) / rate
                    let lines = try await engine.transcribe(samples)
                    if cancelRequested.contains(id) { break }
                    t.lines += lines.map { .init(start: $0.start + offset, end: $0.end + offset, text: $0.text) }
                } catch {
                    errors[id] = "Transcribing stopped: \(error.localizedDescription)"
                    break
                }
            }
            pos = end
            t.doneUpTo = Double(pos) / rate
            t.finished = pos >= total
            transcripts[id] = t
            try? TranscriptStore.save(t, for: id)

            let done = Double(pos - startPos)
            let elapsed = Date().timeIntervalSince(started)
            active = Job(
                id: id,
                doneSeconds: Double(pos) / rate,
                totalSeconds: Double(total) / rate,
                secondsLeft: done > 0 ? elapsed / done * Double(total - pos) : nil
            )
        }
        cancelRequested.remove(id)
        active = nil
    }
}

extension Transcriber {
    /// "about 4 min left"
    nonisolated static func leftText(_ seconds: Double) -> String {
        if seconds < 60 { return "under a minute left" }
        return "about \(Int((seconds / 60).rounded())) min left"
    }
}
