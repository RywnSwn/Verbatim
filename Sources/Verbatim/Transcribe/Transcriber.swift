import Foundation
import Observation

/// Transcribes whole files with Parakeet, one at a time: imported files,
/// "Transcribe again", and recordings whose live text didn't come from
/// Parakeet (Apple's backup engine, or no live text at all).
///
/// Recordings made with Parakeet never come here: their live text is the
/// transcript. Same model as live text, so no second download. A file job
/// waits while a recording is going, so only one copy of the model is in
/// memory (8 GB Mac).
@MainActor
@Observable
final class Transcriber {
    static let shared = Transcriber()

    struct Job: Equatable {
        var id: UUID
        var doneSeconds: Double
        var totalSeconds: Double
        var secondsLeft: Double?
    }

    /// Audio handed to Parakeet at a time. It runs much faster than real time,
    /// so this only decides how often progress, Cancel and edits are looked at.
    static let blockSeconds: Int64 = 4
    /// Name saved in transcript.json.
    static let modelName = "parakeet-unified-en-0.6b"

    private(set) var queue: [UUID] = []
    private(set) var active: Job?
    private(set) var importing: Set<UUID> = []
    private(set) var transcripts: [UUID: Transcript] = [:]
    private(set) var errors: [UUID: String] = [:]
    /// Recordings still getting audio (recording, paused, or in the 10 s Undo
    /// Stop window). File jobs wait until this is empty.
    private(set) var growing: Set<UUID> = []

    @ObservationIgnored private let engine = ParakeetEngine()
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested: Set<UUID> = []

    private init() {}

    /// Called once at launch with the saved recordings, after `LiveTranscriber.start`
    /// (it needs the live text to know which recordings still need text).
    func start(with recordings: [RecordingInfo]) {
        Self.removeOldWhisperModel()
        for r in recordings {
            if let t = TranscriptStore.load(r.id) { transcripts[r.id] = t }
        }
        // Pick up anything left unfinished (app quit, crash, or no Parakeet text yet).
        for r in recordings.reversed() where !r.isActive {
            if let t = transcripts[r.id] {
                if !t.finished, !t.stoppedByUser { queue.append(r.id) }
            } else if needsFilePass(r.id) {
                queue.append(r.id)
            }
        }
        runQueue()
    }

    /// Parakeet finished downloading: start anything that was waiting for it.
    func modelReady() { runQueue() }

    /// The live text isn't Parakeet's (Apple's backup engine wrote some of it),
    /// or there is none: run Parakeet over the audio.
    private func needsFilePass(_ id: UUID) -> Bool {
        guard FileManager.default.fileExists(atPath: RecordingStore.audioURL(id).path) else { return false }
        guard let live = LiveTranscriber.shared.texts[id], !live.lines.isEmpty else { return true }
        return live.engines.contains(AppleSpeechEngine.name)
    }

    /// Whisper (626 MB) was dropped in step 5c. Give the space back once: delete
    /// everything in Models except Parakeet's folder.
    private static func removeOldWhisperModel() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "modelFolder")
        defaults.removeObject(forKey: "modelPrepared")
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let models = support.appending(path: "Verbatim/Models", directoryHint: .isDirectory)
            guard let items = try? fm.contentsOfDirectory(at: models, includingPropertiesForKeys: nil) else { return }
            for item in items where item.lastPathComponent != "Live" {
                try? fm.removeItem(at: item)
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
        // Saved even with nothing done yet, so it doesn't start again by itself
        // on the next launch. The live text (if any) still shows.
        var t = transcripts[id] ?? Transcript(model: Self.modelName)
        guard !t.finished else { return }
        t.stoppedByUser = true
        transcripts[id] = t
        try? TranscriptStore.save(t, for: id)
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

    /// A recording is going, so file jobs wait.
    var isWaitingForRecording: Bool { !growing.isEmpty }

    // MARK: - While recording

    /// Recording started, or carried on after Undo Stop. A file job in progress
    /// stops after its current bit and carries on after Stop.
    func recordingStarted(_ id: UUID) {
        growing.insert(id)
    }

    /// Stopped for good (Undo Stop expired). Parakeet's live text is the
    /// transcript; anything else gets a Parakeet pass now.
    func recordingFinal(_ id: UUID) {
        growing.remove(id)
        if transcripts[id] == nil, needsFilePass(id) {
            enqueue(id)
        } else {
            runQueue()
        }
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

    // MARK: - Running jobs

    private func runQueue() {
        guard workTask == nil, LiveTranscriber.shared.isModelReady, growing.isEmpty, !queue.isEmpty else { return }
        workTask = Task {
            while let id = queue.first, growing.isEmpty {
                let result = await transcribe(id)
                // Waiting for a recording to stop: stays in the queue.
                if result == .done { queue.removeAll { $0 == id } }
            }
            await engine.unload() // free the memory for the recording or the next job
            workTask = nil
            runQueue()
        }
    }

    private enum JobResult { case done, yielded }

    private func transcribe(_ id: UUID) async -> JobResult {
        let audio = RecordingStore.audioURL(id)
        guard FileManager.default.fileExists(atPath: audio.path) else { return .done }
        var t = transcripts[id] ?? Transcript(model: Self.modelName)
        guard !t.finished else { return .done }
        cancelRequested.remove(id)

        let rate = Double(WavReader.rate)
        let total = WavReader.sampleCount(audio)
        var pos = min(Int64(t.doneUpTo * rate), total)
        t.model = Self.modelName
        transcripts[id] = t
        active = Job(id: id, doneSeconds: Double(pos) / rate, totalSeconds: Double(total) / rate)

        do {
            try await engine.begin()
        } catch {
            await engine.unload()
            errors[id] = "Couldn't load the speech model. Verbatim is getting it again."
            LiveTranscriber.shared.modelBroken()
            active = nil
            return .done
        }

        let words = WordFilter(id, from: t.doneUpTo, existing: t.lines)
        let offset = Double(pos) / rate
        let started = Date()
        let startPos = pos
        var lastSave = Date()
        var result = JobResult.done
        var failed = false

        while pos < total {
            if cancelRequested.contains(id) { break }
            if !growing.isEmpty { result = .yielded; break }
            let count = min(Self.blockSeconds * WavReader.rate, total - pos)
            let samples: [Float]
            do {
                samples = try WavReader.samples(audio, from: pos, count: count)
            } catch {
                errors[id] = "Transcribing stopped: \(error.localizedDescription)"
                failed = true
                break
            }
            let out = await engine.feed(samples)
            pos += count
            add(out, to: id, offset: offset, words: words)

            let done = Double(pos - startPos)
            let elapsed = Date().timeIntervalSince(started)
            active = Job(
                id: id,
                doneSeconds: Double(pos) / rate,
                totalSeconds: Double(total) / rate,
                secondsLeft: done > 0 && elapsed > 2 ? elapsed / done * Double(total - pos) : nil
            )
            if Date().timeIntervalSince(lastSave) > 10 {
                if var now = transcripts[id] {
                    now.doneUpTo = min(now.doneUpTo, Double(pos) / rate)
                    try? TranscriptStore.save(now, for: id)
                }
                lastSave = Date()
            }
        }

        // Finish the last words of what was read, even when stopping early, so
        // carrying on later starts cleanly at `pos`.
        add(await engine.end(), to: id, offset: offset, words: words)
        if var now = transcripts[id] {
            now.doneUpTo = Double(pos) / rate
            now.finished = pos >= total && !failed
            // Edited lines up to here (all of them at the end). Later ones still
            // show in the live text until the job carries on.
            now.lines += words.lockedLeft(before: now.finished ? .infinity : now.doneUpTo)
            now.lines.sort { $0.start < $1.start }
            transcripts[id] = now
            try? TranscriptStore.save(now, for: id)
        }
        cancelRequested.remove(id)
        active = nil
        return result
    }

    /// Adds Parakeet's words to the transcript on screen. Re-reads it each time,
    /// so edits and deletes made while it runs are kept.
    private func add(_ out: LiveOutput, to id: UUID, offset: Double, words: WordFilter) {
        guard !out.finals.isEmpty, var t = transcripts[id] else { return }
        for p in out.finals {
            let piece = LivePiece(text: p.text, start: p.start + offset, end: p.end + offset)
            let locked = words.lockedLeft(before: piece.start)
            if !locked.isEmpty {
                t.lines += locked
                t.lines.sort { $0.start < $1.start }
            }
            guard words.keeps(piece) else { continue }
            let editingLast = LiveTranscriber.shared.editing.map { $0.id == id && $0.start == t.lines.last?.start } ?? false
            LineBuilder.add(piece, to: &t.lines, extendLast: !editingLast)
            t.doneUpTo = max(t.doneUpTo, piece.end)
        }
        transcripts[id] = t
    }
}

/// Keeps Ryan's changes to the live text when a recording is transcribed again:
/// words inside lines he deleted are dropped, and lines he edited are kept as
/// he wrote them (locked) instead of Parakeet's words for that bit.
@MainActor
private final class WordFilter {
    /// Extra time around a line, because two passes don't time words exactly the same.
    static let padding = 0.15

    private let skip: [LiveText.Span]
    private var locked: [Transcript.Line]

    /// `existing`: lines already in the transcript (carrying on after Cancel or
    /// a recording), so edited lines added last time aren't added twice.
    init(_ id: UUID, from seconds: Double, existing: [Transcript.Line]) {
        let live = LiveTranscriber.shared.texts[id]
        locked = (live?.lines ?? []).filter { line in
            line.isLocked && line.end > seconds
                && !existing.contains { $0.start == line.start && $0.text == line.text }
        }
        skip = (live?.removed ?? []) + locked.map { LiveText.Span(start: $0.start, end: $0.end) }
    }

    func keeps(_ piece: LivePiece) -> Bool {
        let mid = (piece.start + piece.end) / 2
        return !skip.contains { mid >= $0.start - Self.padding && mid <= $0.end + Self.padding }
    }

    /// Edited lines that start before `seconds` and haven't been added yet.
    func lockedLeft(before seconds: Double) -> [Transcript.Line] {
        let due = locked.filter { $0.start < seconds }
        locked.removeAll { $0.start < seconds }
        return due
    }
}

extension Transcriber {
    /// "about 4 min left"
    nonisolated static func leftText(_ seconds: Double) -> String {
        if seconds < 60 { return "under a minute left" }
        return "about \(Int((seconds / 60).rounded())) min left"
    }
}
