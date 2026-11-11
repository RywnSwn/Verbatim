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
    /// The line being edited right now (recording, line start). New words never go into it.
    var editing: (id: UUID, start: Double)?

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
            SpeakerModel.shared.startIfNeeded()
            WordModel.shared.startIfNeeded()
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

    // MARK: - Editing lines

    /// Replaces the line that starts at `start`. Returns the old line.
    @discardableResult
    func replaceLine(_ id: UUID, start: Double, with line: Transcript.Line) -> Transcript.Line? {
        guard var t = texts[id], let i = t.lines.firstIndex(where: { $0.start == start }) else { return nil }
        let old = t.lines[i]
        t.lines[i] = line
        commit(t, id)
        return old
    }

    func removeLine(_ id: UUID, start: Double) -> Transcript.Line? {
        guard var t = texts[id], let i = t.lines.firstIndex(where: { $0.start == start }) else { return nil }
        let old = t.lines.remove(at: i)
        t.removed = (t.removed ?? []) + [LiveText.Span(start: old.start, end: old.end)]
        commit(t, id)
        return old
    }

    func insertLine(_ id: UUID, _ line: Transcript.Line) {
        guard var t = texts[id] else { return }
        let i = t.lines.firstIndex { $0.start > line.start } ?? t.lines.count
        t.lines.insert(line, at: i)
        t.removed?.removeAll { $0.start == line.start }
        commit(t, id)
    }

    private func commit(_ t: LiveText, _ id: UUID) {
        texts[id] = t
        try? LiveStore.save(t, for: id)
    }

    func reload(_ id: UUID) { texts[id] = LiveStore.load(id) }

    // MARK: - Speakers (step 7)

    /// The speaker model starts listening on this recording again. Returns the
    /// number to add to its voices (0 to 3), so they don't mix with earlier ones.
    /// `names`: voices the speaker model already knows (step 7c), by its number.
    func newVoiceSession(_ id: UUID, names: [Int: String] = [:]) -> Int {
        var t = texts[id] ?? LiveText()
        let n = t.voiceSessions ?? 0
        t.voiceSessions = n + 1
        if !names.isEmpty {
            var all = t.voiceNames ?? [:]
            for (slot, name) in names { all["\(n * 4 + slot)"] = name }
            t.voiceNames = all
        }
        commit(t, id)
        return n * 4
    }

    /// Ryan named a whole voice ("Change them too"). nil takes it back.
    func setVoiceName(_ id: UUID, voice: Int, to choice: String?) {
        guard var t = texts[id] else { return }
        var names = t.voiceNames ?? [:]
        names["\(voice)"] = choice
        t.voiceNames = names.isEmpty ? nil : names
        commit(t, id)
    }

    /// Voices from the speaker model going over the whole file. Lines where
    /// the voice changes partway are split there. Names Ryan gave voices before
    /// are dropped (the numbers are new); names he gave single lines stay.
    func applyVoices(_ id: UUID, frames: VoiceFrames, base: Int, names: [Int: String] = [:]) {
        guard var t = texts[id] else { return }
        t.lines = Speakers.relabel(t.lines, frames: frames, base: base)
        var known: [String: String] = [:]
        for (slot, name) in names { known["\(base + slot)"] = name }
        t.voiceNames = known.isEmpty ? nil : known
        t.speakersFound = true
        commit(t, id)
    }

    /// Marks the speaker pass done without changing anything (no audio, failed).
    func markSpeakersFound(_ id: UUID) {
        guard var t = texts[id] else { return }
        t.speakersFound = true
        commit(t, id)
    }

    // MARK: - Going over a file (Transcriber)

    /// Replaces the whole text (Transcribe again, starting a file pass).
    func setText(_ t: LiveText, for id: UUID) {
        commit(t, id)
    }

    /// Words from going over the file, added to whatever is on screen now (so
    /// edits made meanwhile are kept), plus progress. Saved every time.
    /// Ryan's edits from before "Transcribe again" are kept: words inside a
    /// line he deleted are dropped, and a line he edited goes back in as he
    /// wrote it instead of Parakeet's words for that bit.
    func addPass(_ words: [LivePiece], fixes: [PhraseFix] = [], offset: Double, to id: UUID, doneUpTo: Double?, finished: Bool) {
        var t = texts[id] ?? LiveText(pass: LiveText.FilePass())
        var pass = t.pass ?? LiveText.FilePass()
        var keep = pass.keep ?? []
        let removed = t.removed ?? []
        for p in words {
            let word = LivePiece(text: p.text, start: p.start + offset, end: p.end + offset)
            while let first = keep.first, first.start <= word.start {
                t.lines.append(keep.removeFirst())
            }
            let mid = (word.start + word.end) / 2
            let inEdited = (t.lines.last.map { $0.isLocked && mid <= $0.end } ?? false)
                || keep.contains { mid >= $0.start && mid <= $0.end }
            if inEdited || removed.contains(where: { mid >= $0.start && mid <= $0.end }) { continue }
            let extend = !(editing?.id == id && editing?.start == t.lines.last?.start)
            LineBuilder.add(word, to: &t.lines, extendLast: extend)
        }
        fix(&t, id, spotted: fixes, newWords: !words.isEmpty)
        if finished {
            t.lines += keep
            keep = []
        }
        pass.keep = keep.isEmpty ? nil : keep
        if !words.isEmpty, t.engines.last != ParakeetEngine.name { t.engines.append(ParakeetEngine.name) }
        if let doneUpTo { pass.doneUpTo = max(pass.doneUpTo, doneUpTo) }
        pass.finished = finished
        t.pass = pass
        commit(t, id)
    }

    // MARK: - Fixes (step 8)

    /// Name fixes from the word spotter, then Ryan's fix rules on the newest
    /// lines. Never touches edited lines or the line being edited.
    private func fix(_ t: inout LiveText, _ id: UUID, spotted: [PhraseFix], newWords: Bool) {
        let skip = editing?.id == id ? editing?.start : nil
        for f in spotted { Fixes.applySpotted(f, to: &t.lines, skip: skip) }
        if newWords || !spotted.isEmpty {
            Fixes.applyRules(WordList.shared.fixes, to: &t.lines, skip: skip)
        }
    }

    /// Ryan said Remember: the rule fixes the rest of this transcript too.
    /// Returns each changed line as it was and as it is now, for Undo.
    func applyRule(_ rule: PhraseFix, to id: UUID) -> [(old: Transcript.Line, new: Transcript.Line)] {
        guard var t = texts[id] else { return [] }
        let skip = editing?.id == id ? editing?.start : nil
        var changed: [(old: Transcript.Line, new: Transcript.Line)] = []
        for i in t.lines.indices where !t.lines[i].isLocked && t.lines[i].start != skip {
            if let fixed = Fixes.apply(rule, to: t.lines[i]) {
                changed.append((old: t.lines[i], new: fixed))
                t.lines[i] = fixed
            }
        }
        if !changed.isEmpty { commit(t, id) }
        return changed
    }

    /// Undo of `applyRule`: lines that are still exactly as it left them go back.
    func undoRule(_ changed: [(old: Transcript.Line, new: Transcript.Line)], in id: UUID) {
        guard var t = texts[id] else { return }
        for c in changed {
            if let i = t.lines.firstIndex(where: { $0 == c.new }) { t.lines[i] = c.old }
        }
        commit(t, id)
    }

    // MARK: - From the runner

    fileprivate func setStatus(_ s: Status?, run: Int) {
        guard run == generation else { return }
        status = s
    }

    fileprivate func apply(_ out: LiveOutput, offset: Double, engine: String, to id: UUID, run: Int) {
        guard var t = texts[id] else { return }
        for p in out.finals {
            let extend = !(editing?.id == id && editing?.start == t.lines.last?.start)
            LineBuilder.add(LivePiece(text: p.text, start: p.start + offset, end: p.end + offset), to: &t.lines, extendLast: extend)
        }
        fix(&t, id, spotted: out.fixes, newWords: !out.finals.isEmpty)
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
                Transcriber.shared.modelReady()
                SpeakerModel.shared.startIfNeeded()
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
    private let speakers = SpeakerEngine()
    /// Where the speaker model started listening (seconds into audio.wav), and
    /// the number added to its voices. nil = not listening (model not here).
    private var speakerStart: Double?
    private var voiceBase = 0

    func run(id: UUID, run: Int, stream: AsyncStream<LiveInput>, position start: Int64) async {
        var position = start
        var engine: (any LiveEngine)?
        var name = ""
        var offset = 0.0
        var nextTry: Int64 = 0
        await startSpeakers(id: id, position: position)

        for await input in stream {
            switch input {
            case .samples(let samples):
                // Speakers first: then it's ahead of the words that need it.
                if speakerStart != nil { await speakers.feed(samples) }
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
            if speakerStart != nil { await speakers.finish() }
            await deliver(await engine.end(), offset: offset, engine: name, id: id, run: run)
        }
        await parakeet.unload() // free the memory for files waiting to be transcribed
        await speakers.unload()
        speakerStart = nil
        await MainActor.run { LiveTranscriber.shared.finished(id, run: run) }
    }

    private func deliver(_ out: LiveOutput, offset: Double, engine: String, id: UUID, run: Int) async {
        guard !out.finals.isEmpty || out.volatile != nil || !out.fixes.isEmpty else { return }
        var labelled = out
        if let speakerStart, !out.finals.isEmpty {
            labelled.finals = await speakers.label(out.finals, shift: offset - speakerStart, base: voiceBase)
        }
        let ready = labelled
        await MainActor.run { LiveTranscriber.shared.apply(ready, offset: offset, engine: engine, to: id, run: run) }
    }

    /// The speaker model listens for the whole run (Pause just means no audio
    /// for a while), if it's downloaded. Without it, lines have no speaker.
    private func startSpeakers(id: UUID, position: Int64) async {
        speakerStart = nil
        guard await MainActor.run(body: { SpeakerModel.shared.isReady }) else { return }
        do {
            let known = await MainActor.run { VoiceLibrary.shared.knownVoices() }
            let names = try await speakers.begin(known: known)
            voiceBase = await MainActor.run { LiveTranscriber.shared.newVoiceSession(id, names: names) }
            speakerStart = Double(position) / 16_000
        } catch {
            await speakers.unload()
            await MainActor.run { SpeakerModel.shared.broken() }
        }
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
