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
        /// The bit of audio being checked right now (seconds into audio.wav).
        var pieceStart: Double = 0
        var pieceEnd: Double = 0
    }

    /// Piece size for a finished recording or an imported file.
    static let pieceSeconds: Int64 = 120
    /// While recording: check every 5 minutes of new audio.
    static let chunkSeconds: Int64 = 300
    /// While recording: leave the newest audio alone until live text for it is
    /// final, so the cut can be placed between live lines.
    static let settleSeconds: Int64 = 15
    /// Each piece starts this much before the cut, so Whisper hears the first
    /// word whole. Words before the cut are dropped when merging.
    static let overlapSeconds = 1.0

    private(set) var modelState: ModelState = .downloading(fraction: 0, secondsLeft: nil)
    private(set) var queue: [UUID] = []
    private(set) var active: Job?
    private(set) var importing: Set<UUID> = []
    private(set) var transcripts: [UUID: Transcript] = [:]
    private(set) var errors: [UUID: String] = [:]
    /// Recordings still getting audio (recording, paused, or in the 10 s Undo Stop
    /// window). Checked in 5 minute chunks; the newest bit waits for Stop.
    private(set) var growing: Set<UUID> = []
    /// Low Power Mode: chunks wait during recording and catch up at Stop.
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private let engine = WhisperEngine()
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested: Set<UUID> = []
    @ObservationIgnored private var progressSamples: [(Date, Double)] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var powerObserver: NSObjectProtocol?

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

    private init() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Transcriber.shared.powerChanged() }
        }
    }

    private func powerChanged() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if !lowPower {
            for id in growing where chunkReady(id) { enqueue(id) }
        }
    }

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
        guard active?.id != id, !growing.contains(id) else { return }
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
        growing.remove(id)
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

    func isGrowing(_ id: UUID) -> Bool { growing.contains(id) }

    // MARK: - While recording

    /// Recording started, or carried on after Undo Stop.
    func recordingStarted(_ id: UUID) {
        growing.insert(id)
    }

    /// Called every few seconds while recording. Starts a chunk once there are
    /// 5 minutes of new audio.
    func audioGrew(_ id: UUID) {
        guard growing.contains(id), active?.id != id, !queue.contains(id), chunkReady(id) else { return }
        enqueue(id)
    }

    /// Stopped for good (Undo Stop expired): check the rest, to the end.
    func recordingFinal(_ id: UUID) {
        growing.remove(id)
        enqueue(id)
    }

    /// A growing recording has a full chunk waiting.
    private func chunkReady(_ id: UUID) -> Bool {
        guard growing.contains(id), !lowPower, transcripts[id]?.stoppedByUser != true else { return false }
        let total = WavReader.sampleCount(RecordingStore.audioURL(id))
        let done = Int64((transcripts[id]?.doneUpTo ?? 0) * Double(WavReader.rate))
        return total - done >= (Self.chunkSeconds + Self.settleSeconds) * WavReader.rate
    }

    /// Where to end a chunk: in the longest gap between live lines in the 30 s
    /// before `target` (so live lines never get split), at its quietest moment.
    /// Without live text, the quietest moment in the 20 s before `target`.
    private func cutPoint(_ id: UUID, audio: URL, target: Int64, after pos: Int64) -> Int64 {
        let rate = Double(WavReader.rate)
        let high = Double(target) / rate
        let low = max(high - 30, Double(pos) / rate + 60)
        let lines = LiveTranscriber.shared.texts[id]?.lines ?? []
        var best: (from: Double, to: Double)?
        for (a, b) in zip(lines, lines.dropFirst()) where b.start > a.end {
            let mid = (a.end + b.start) / 2
            guard mid > low, mid < high else { continue }
            if best == nil || b.start - a.end > best!.to - best!.from { best = (a.end, b.start) }
        }
        if let best, best.to - best.from >= 0.25 {
            let cut = WavReader.quietPoint(audio, from: Int64(best.from * rate), to: Int64(best.to * rate))
            if cut > pos { return cut }
        }
        let cut = WavReader.quietPoint(audio, before: target, searchSeconds: 20)
        return cut > pos ? cut : target
    }

    // MARK: - Editing lines

    /// Replaces the line that starts at `start`. Returns the old line.
    @discardableResult
    func replaceLine(_ id: UUID, start: Double, with line: Transcript.Line) -> Transcript.Line? {
        guard var t = transcripts[id], let i = t.lines.firstIndex(where: { $0.start == start }) else { return nil }
        let old = t.lines[i]
        t.lines[i] = line
        commit(t, id)
        return old
    }

    func removeLine(_ id: UUID, start: Double) -> Transcript.Line? {
        guard var t = transcripts[id], let i = t.lines.firstIndex(where: { $0.start == start }) else { return nil }
        let old = t.lines.remove(at: i)
        commit(t, id)
        return old
    }

    func insertLine(_ id: UUID, _ line: Transcript.Line) {
        guard var t = transcripts[id] else { return }
        let i = t.lines.firstIndex { $0.start > line.start } ?? t.lines.count
        t.lines.insert(line, at: i)
        commit(t, id)
    }

    private func commit(_ t: Transcript, _ id: UUID) {
        transcripts[id] = t
        try? TranscriptStore.save(t, for: id)
    }

    private func runQueue() {
        guard workTask == nil, modelState == .ready, !queue.isEmpty else { return }
        workTask = Task {
            while let id = nextJob() {
                let result = await transcribe(id)
                // A finished file, or a recording with no full chunk left: done for
                // now. Skipped for the recording in progress: comes back later.
                if result == .done { queue.removeAll { $0 == id } }
            }
            await engine.unload() // free the memory until the next chunk or recording
            workTask = nil
            runQueue()
        }
    }

    /// The recording in progress goes first, so its text upgrades during class
    /// even while an imported file is being transcribed.
    private func nextJob() -> UUID? {
        queue.first { growing.contains($0) && chunkReady($0) } ?? queue.first
    }

    private enum JobResult { case done, yielded }

    private func transcribe(_ id: UUID) async -> JobResult {
        let audio = RecordingStore.audioURL(id)
        guard FileManager.default.fileExists(atPath: audio.path) else { return .done }
        var t = transcripts[id] ?? Transcript(model: WhisperEngine.variant)
        guard !t.finished else { return .done }
        if growing.contains(id), !chunkReady(id) { return .done }
        cancelRequested.remove(id)

        let rate = Double(WavReader.rate)
        var total = WavReader.sampleCount(audio)
        var pos = min(Int64(t.doneUpTo * rate), total)
        active = Job(id: id, doneSeconds: Double(pos) / rate, totalSeconds: Double(total) / rate)

        guard let folder = modelFolder else { active = nil; return .done }
        do {
            try await engine.load(folder: folder, base: Self.modelBase)
        } catch {
            errors[id] = "Couldn't load the model: \(error.localizedDescription)"
            active = nil
            return .done
        }

        let started = Date()
        let startPos = pos
        var result = JobResult.done
        while !cancelRequested.contains(id) {
            total = WavReader.sampleCount(audio)
            let isGrowing = growing.contains(id)
            var end: Int64
            if isGrowing {
                guard chunkReady(id) else { break }
                end = cutPoint(id, audio: audio, target: pos + Self.chunkSeconds * WavReader.rate, after: pos)
            } else {
                guard pos < total else { break }
                end = min(pos + Self.pieceSeconds * WavReader.rate, total)
                if end < total { end = WavReader.quietPoint(audio, before: end) }
                if end <= pos { end = min(pos + Self.pieceSeconds * WavReader.rate, total) }
            }
            active = Job(
                id: id,
                doneSeconds: Double(pos) / rate,
                totalSeconds: Double(total) / rate,
                secondsLeft: active?.secondsLeft,
                pieceStart: Double(pos) / rate,
                pieceEnd: Double(end) / rate
            )

            if end - pos >= WavReader.rate / 2 { // skip a final crumb under half a second
                do {
                    let from = max(0, pos - Int64(Self.overlapSeconds * rate))
                    let samples = try WavReader.samples(audio, from: from, count: end - from)
                    let segments = try await engine.transcribe(samples, prompt: promptText(id, t, before: Double(pos) / rate))
                    if cancelRequested.contains(id) { break }
                    await waitWhileEditing(id, before: Double(end) / rate)
                    if cancelRequested.contains(id) { break }
                    // Start from what's on screen now, so edits and deletes made
                    // while this piece was transcribing are kept.
                    t.lines = (transcripts[id]?.lines ?? t.lines)
                        + merged(id, segments, offset: Double(from) / rate, from: Double(pos) / rate, to: Double(end) / rate)
                } catch {
                    errors[id] = "Transcribing stopped: \(error.localizedDescription)"
                    break
                }
            }
            pos = end
            t.doneUpTo = Double(pos) / rate
            t.finished = !growing.contains(id) && pos >= WavReader.sampleCount(audio)
            transcripts[id] = t
            try? TranscriptStore.save(t, for: id)

            let done = Double(pos - startPos)
            let elapsed = Date().timeIntervalSince(started)
            active = Job(
                id: id,
                doneSeconds: Double(pos) / rate,
                totalSeconds: Double(total) / rate,
                secondsLeft: !isGrowing && done > 0 ? elapsed / done * Double(max(0, total - pos)) : nil
            )

            // The recording in progress has a chunk waiting: do that first, then
            // carry on with this one.
            if !isGrowing, queue.contains(where: { $0 != id && chunkReady($0) }) {
                result = .yielded
                break
            }
        }
        cancelRequested.remove(id)
        active = nil
        return result
    }

    /// The last bit of checked text before `seconds`, as context for Whisper.
    /// Step 8 adds the word list here.
    private func promptText(_ id: UUID, _ t: Transcript, before seconds: Double) -> String? {
        let previous = (transcripts[id] ?? t).lines.filter { $0.end <= seconds + 0.5 }.suffix(3)
        let text = previous.map(\.text).joined(separator: " ")
        return text.isEmpty ? nil : String(text.suffix(150))
    }

    /// If Ryan is editing a live line in this piece, wait until he's done, so
    /// his edit is kept (the line moves into the checked text locked).
    private func waitWhileEditing(_ id: UUID, before seconds: Double) async {
        while let e = LiveTranscriber.shared.editing, e.id == id, e.start < seconds, !cancelRequested.contains(id) {
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// Whisper's words for [from, to), minus lines Ryan deleted, plus lines he
    /// edited in the live text (kept as he wrote them), plus live lines Whisper
    /// skipped.
    private func merged(_ id: UUID, _ segments: [WhisperSegment], offset: Double, from: Double, to: Double) -> [Transcript.Line] {
        let live = LiveTranscriber.shared.texts[id]
        let lockedLines = (live?.lines ?? []).filter(\.isLocked)
        let overlaps = { (s: Double, e: Double) in e >= offset && s <= to }
        let skip = (live?.removed ?? []).filter { overlaps($0.start, $0.end) }
            + lockedLines.filter { overlaps($0.start, $0.end) }.map { ChunkMerge.Span(start: $0.start, end: $0.end) }
        let keep = lockedLines.filter { $0.middle >= from && $0.middle < to }
        let others = (live?.lines ?? []).filter { !$0.isLocked && $0.end >= offset - 20 && $0.start <= to + 20 }
        return ChunkMerge.lines(segments, offset: offset, keepFrom: from, skip: skip, locked: keep, live: others, keepTo: to)
    }
}

extension Transcriber {
    /// "about 4 min left"
    nonisolated static func leftText(_ seconds: Double) -> String {
        if seconds < 60 { return "under a minute left" }
        return "about \(Int((seconds / 60).rounded())) min left"
    }
}
