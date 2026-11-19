import Foundation
import Observation

/// Audio for the live engine: samples as they are saved, and a marker when the
/// mic stops (Pause, sleep) so the last words get finished.
enum LiveInput: Sendable {
    case samples([Float])
    case flush
}

/// Audio for one run of the live engine (recording start to Stop). The mic
/// hands over about 47 small bits a second. The runner takes everything that
/// is waiting at once (up to `LiveRunner.biggestBite`), so when the models
/// fall behind (loading at the start, a slow moment) they catch up in a few
/// big steps instead of hundreds of tiny ones, each with its own trip to
/// every model and to the screen.
final class LiveQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [LiveInput] = []
    private var waiting = 0
    private var closed = false
    /// One wake-up per batch of new audio (more audio while the runner is
    /// busy just means "there's more").
    let wakeups: AsyncStream<Void>
    private let wake: AsyncStream<Void>.Continuation

    init() {
        (wakeups, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    func put(_ input: LiveInput) {
        let ok = lock.withLock {
            guard !closed else { return false }
            items.append(input)
            if case .samples(let s) = input { waiting += s.count }
            return true
        }
        if ok { wake.yield() }
    }

    /// Seconds of audio waiting in this queue.
    var waitingSeconds: Double { lock.withLock { Double(waiting) / 16_000 } }

    /// The next thing to do: a flush on its own, or all the samples waiting
    /// before the next flush, joined, up to about `max` samples.
    func take(max: Int) -> LiveInput? {
        lock.withLock {
            guard let first = items.first else { return nil }
            if case .flush = first {
                items.removeFirst()
                return .flush
            }
            var joined: [Float] = []
            var n = 0
            while n < items.count, joined.count < max, case .samples(let s) = items[n] {
                joined += s
                n += 1
            }
            items.removeFirst(n)
            waiting -= joined.count
            return .samples(joined)
        }
    }

    func close() {
        lock.withLock { closed = true }
        wake.finish()
    }
}

/// Hands samples from the audio thread to the live engine, in order.
final class LiveFeed: @unchecked Sendable {
    /// The one feed, reachable from any thread.
    static let shared = LiveFeed()
    private let lock = NSLock()
    private var queue: LiveQueue?
    /// Samples handed over, and samples the engines are done with. The gap
    /// is how far live text is behind the mic (shown by `HitchMeter`).
    private var given: Int64 = 0
    private var done: Int64 = 0
    private var worstBehind: Int64 = 0
    /// When the last bit of audio came in, and the longest wait between two
    /// (should be far under a second; long = the mic side stalled).
    private var lastAt: UInt64 = 0
    private var worstGap: UInt64 = 0
    /// How the last start went (seconds after Start): shown by `HitchMeter`.
    private var openedAt: UInt64 = 0
    private var startTimes: [(String, Double)] = []

    func open() -> LiveQueue {
        let q = LiveQueue()
        lock.withLock {
            queue?.close()
            queue = q
            given = 0
            done = 0
            lastAt = 0
            openedAt = DispatchTime.now().uptimeNanoseconds
            startTimes = []
        }
        return q
    }

    var isOpen: Bool { lock.withLock { queue != nil } }

    func yield(_ input: LiveInput) {
        let q: LiveQueue? = lock.withLock {
            guard let queue else { return nil }
            if case .samples(let s) = input {
                let now = DispatchTime.now().uptimeNanoseconds
                if lastAt != 0 { worstGap = max(worstGap, now - lastAt) }
                lastAt = now
                given += Int64(s.count)
                worstBehind = max(worstBehind, given - done)
            }
            return queue
        }
        q?.put(input)
    }

    /// The engines finished this many samples.
    func finished(_ samples: Int) {
        lock.withLock { done += Int64(samples) }
    }

    /// Something got ready during this recording's start ("Parakeet
    /// listening", "first words"). Only the first time each.
    func mark(_ what: String) {
        lock.withLock {
            guard openedAt != 0, !startTimes.contains(where: { $0.0 == what }) else { return }
            startTimes.append((what, Double(DispatchTime.now().uptimeNanoseconds - openedAt) / 1e9))
        }
    }

    /// "Parakeet listening 3.1 s, speakers 4.0 s, first words 6.2 s" for the last start.
    func startText() -> String {
        lock.withLock {
            guard !startTimes.isEmpty else { return "no recording started since launch" }
            return startTimes.map { String(format: "%@ %.1f s", $0.0, $0.1) }.joined(separator: ", ")
        }
    }

    /// Pause and Stop: the wait until the next audio isn't a stall.
    func micPaused() { lock.withLock { lastAt = 0 } }

    func worstGapSeconds() -> Double {
        lock.withLock {
            let out = Double(worstGap) / 1e9
            worstGap = 0
            return out
        }
    }

    /// Seconds of audio waiting right now, and the most since the last call.
    func behind() -> (now: Double, worst: Double) {
        lock.withLock {
            let out = (Double(max(0, given - done)) / 16_000, Double(worstBehind) / 16_000)
            worstBehind = max(0, given - done)
            return out
        }
    }

    func close() {
        lock.withLock {
            queue?.close()
            queue = nil
        }
    }
}

/// One recording's text, watched on its own (see `LiveTranscriber.texts`).
@MainActor
@Observable
final class LiveBox {
    var text: LiveText
    init(_ text: LiveText) { self.text = text }
}

/// Read-only access to the texts: `live.texts[id]`.
@MainActor
struct LiveTexts {
    fileprivate let owner: LiveTranscriber
    subscript(id: UUID) -> LiveText? { owner.text(id) }
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
    /// Each recording's text, read as `texts[id]`. Each one is watched on
    /// its own: a new live word redraws only views showing that recording,
    /// not every view that reads any text (it used to be one dictionary, so
    /// every word redrew most of the window).
    /// A text is read from disk the first time something asks for it (the
    /// recording is opened, copied, exported...), not at launch: a year of
    /// classes is a lot to read before the window can show. Launch only
    /// reads `TextIndex` (see `facts`).
    var texts: LiveTexts { LiveTexts(owner: self) }
    @ObservationIgnored private var boxes: [UUID: LiveBox] = [:]
    /// Recordings known to have no live.json (not read again each time).
    @ObservationIgnored private var noFile: Set<UUID> = []
    /// Facts about every recording's text, also the ones not read yet.
    /// Missing = still being checked in the background (first launch after
    /// the update, or the file changed while Verbatim was closed).
    @ObservationIgnored private var index: [UUID: TextIndex.Entry] = [:]
    @ObservationIgnored private var indexSaveTask: Task<Void, Never>?
    /// Goes up when facts change, for anything that read them from the index.
    private var factsChanged = 0
    /// Goes up when a recording's text is added or removed (not when it
    /// changes), so a view waiting for a text that isn't there yet hears of it.
    private var added = 0
    /// Words Apple's engine is still working out. Shown after the last line.
    private(set) var volatile = ""
    /// Live text is more than a few seconds behind the mic (the models were
    /// still loading, or had a slow moment) and is catching up.
    private(set) var catchingUp = false
    private(set) var activeID: UUID?
    /// The line being edited right now (recording, line start). New words never go into it.
    var editing: (id: UUID, start: Double)?

    /// Written to from the audio thread.
    nonisolated let feed = LiveFeed.shared

    @ObservationIgnored private let runner = LiveRunner()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var progressSamples: [(Date, Double)] = []
    @ObservationIgnored private var lastSave = Date.distantPast
    /// One line for every live.json save (see `write`).
    nonisolated private static let disk = DispatchQueue(label: "Verbatim.live-save", qos: .utility)
    /// Counts saves per recording, so a slow background save that finishes
    /// late doesn't put old facts in the index.
    @ObservationIgnored private var writes: [UUID: Int] = [:]
    @ObservationIgnored private var warnedSave: Set<UUID> = []
    /// Counts recording starts, so a finishing earlier run (before Undo Stop)
    /// can't clear the status of the new one.
    @ObservationIgnored private var generation = 0

    private static let preparedKey = "liveModelPrepared"

    var isModelReady: Bool { modelState == .ready }

    private init() {}

    /// Called once at launch with the saved recordings. Reads only the small
    /// index; texts it has nothing (current) on are checked in the background.
    func start(with recordings: [RecordingInfo]) {
        let saved = TextIndex.load()
        var toCheck: [UUID] = []
        for r in recordings {
            guard let stamp = TextIndex.stamp(r.id) else {
                noFile.insert(r.id)
                continue
            }
            if let entry = saved[r.id], entry.stamp.matches(stamp) {
                index[r.id] = entry
            } else {
                toCheck.append(r.id)
            }
        }
        // Drops recordings that are gone, and saves the first index.
        if index.count != saved.count || !toCheck.isEmpty { saveIndexSoon() }
        checkInBackground(toCheck)
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
        if texts[id] == nil { put(LiveText(), id) }
        generation += 1
        let run = generation
        catchingUp = false
        let queue = feed.open()
        let previous = runTask
        let runner = runner
        runTask = Task {
            await previous?.value
            await Transcriber.shared.modelsFreed()
            await runner.run(id: id, run: run, queue: queue, position: samples)
        }
    }

    /// Start page open: load the live models now, so Record starts listening
    /// at once instead of loading them first (Ryan, 2026-11-19: "a few
    /// seconds" before any words). Not while recording or while a file is
    /// being transcribed (one Parakeet at a time on 8 GB). Runs in the same
    /// line as recordings, so Record pressed mid-load just waits for it.
    func warmUp() {
        guard modelState == .ready, activeID == nil, Transcriber.shared.isIdle else { return }
        let previous = runTask
        let runner = runner
        runTask = Task {
            await previous?.value
            await runner.warm()
        }
    }

    /// A file is about to be transcribed: free the warm models first.
    func coolDown() async {
        guard activeID == nil else { return }
        let previous = runTask
        let runner = runner
        let task = Task {
            await previous?.value
            await runner.cool()
        }
        runTask = task
        await task.value
    }

    /// The mic stopped (Pause or sleep): finish the last words.
    func micStopped() {
        feed.micPaused()
        feed.yield(.flush)
    }

    func recordingStopped() {
        feed.close()
    }

    func lines(_ id: UUID) -> [Transcript.Line] { texts[id]?.lines ?? [] }

    func forget(_ id: UUID) { put(nil, id) }

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
        put(t, id)
        write(t, id)
    }

    /// Saves live.json and keeps the index in step with it. All saves go
    /// through one line (`disk`), so an older text can never land on top of
    /// a newer one. `background`: the save every 10 s while recording, so
    /// writing a long class doesn't hold up the window.
    private func write(_ t: LiveText, _ id: UUID, background: Bool = false) {
        let n = (writes[id] ?? 0) + 1
        writes[id] = n
        guard background else {
            let saved = Self.disk.sync { (try? LiveStore.save(t, for: id)) != nil }
            if saved { remember(t, id) } else { saveFailed(id) }
            return
        }
        Self.disk.async {
            let saved = (try? LiveStore.save(t, for: id)) != nil
            Task { @MainActor in
                let me = LiveTranscriber.shared
                guard me.writes[id] == n else { return } // a newer save came after
                if saved { me.remember(t, id) } else { me.saveFailed(id) }
            }
        }
    }

    /// Says it once per recording, not every 10 s.
    private func saveFailed(_ id: UUID) {
        guard warnedSave.insert(id).inserted else { return }
        RecorderModel.shared.flash("Couldn't save the text. The audio is safe, and Verbatim keeps trying.")
    }

    /// Before quitting: the text of the recording in progress, and every save
    /// still waiting, are on disk when this returns.
    func saveNow() {
        if let id = activeID, let t = texts[id], !t.lines.isEmpty { write(t, id) }
        Self.disk.sync {}
        saveIndexNow()
    }

    /// Stop and Quit: the live run goes through the audio it hadn't got to
    /// yet (it may have been a few seconds behind), then saves. Gives up
    /// after `seconds`: the audio file is complete either way.
    func finishBeforeQuit(upTo seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while activeID != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        saveNow()
    }

    /// The file on disk changed (Put Back, Undo of Delete All): it's read
    /// again when something asks for it, and its facts in the background
    /// (Undo of Delete All puts back every recording at once).
    func reload(_ id: UUID) {
        noFile.remove(id)
        index[id] = nil
        boxes[id] = nil
        added += 1 // views showing it read it again
        checkInBackground([id], atLaunch: false)
    }

    /// The one place texts change. nil removes it.
    private func put(_ t: LiveText?, _ id: UUID) {
        if let t {
            noFile.remove(id)
            if let box = boxes[id] {
                box.text = t
            } else {
                boxes[id] = LiveBox(t)
                added += 1
            }
        } else {
            noFile.insert(id)
            index[id] = nil
            if boxes.removeValue(forKey: id) != nil { added += 1 }
        }
    }

    fileprivate func text(_ id: UUID) -> LiveText? {
        _ = added // watch for this text being added or removed
        if let box = boxes[id] { return box.text }
        guard !noFile.contains(id) else { return nil }
        // First time anything asks: read it now. Not a change anyone needs
        // to hear about (it was on disk all along), so `added` stays.
        guard let t = LiveStore.load(id) else {
            noFile.insert(id)
            return nil
        }
        let box = LiveBox(t)
        boxes[id] = box
        return box.text // read through the box, so this view hears its changes
    }

    // MARK: - Facts for launch (TextIndex)

    /// What the Transcriber needs to know about a recording's text, without
    /// reading it. nil = not known yet (being checked in the background; the
    /// Transcriber hears `textChecked` when it is).
    func facts(_ id: UUID) -> TextFacts? {
        _ = added
        if let box = boxes[id] { return TextFacts(box.text) }
        _ = factsChanged
        if noFile.contains(id) { return TextFacts() }
        return index[id]?.facts
    }

    private func remember(_ t: LiveText?, _ id: UUID) {
        guard let stamp = TextIndex.stamp(id) else { return }
        let entry = TextIndex.Entry(facts: TextFacts(t), stamp: stamp)
        guard index[id] != entry else { return }
        if index[id]?.facts != entry.facts { factsChanged += 1 }
        index[id] = entry
        saveIndexSoon()
    }

    /// One save for a burst of changes (live text saves every 10 s, a file
    /// pass every 30 s of audio). If Verbatim quits before it, the next
    /// launch sees the stamps don't match and checks those texts again.
    private func saveIndexSoon() {
        guard indexSaveTask == nil else { return }
        indexSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            indexSaveTask = nil
            saveIndexNow()
        }
    }

    /// Also called when Verbatim quits. Small (a few hundred bytes per
    /// recording), so it's written right here.
    func saveIndexNow() {
        indexSaveTask?.cancel()
        indexSaveTask = nil
        try? TextIndex.save(index)
    }

    /// Reads texts the index has nothing current on, one at a time, off the
    /// main thread, so the window shows right away. The first launch after
    /// this update does all of them (a few seconds for a year of classes).
    private func checkInBackground(_ ids: [UUID], atLaunch: Bool = true) {
        guard !ids.isEmpty else { return }
        if atLaunch { LaunchTimer.shared.mark("texts to check", detail: "\(ids.count)") }
        Task.detached(priority: .utility) {
            for id in ids {
                let stamp = TextIndex.stamp(id)
                let facts = TextFacts(stamp == nil ? nil : LiveStore.load(id))
                await LiveTranscriber.shared.checked(id, facts, stamp)
            }
            if atLaunch { LaunchTimer.shared.mark("texts checked", detail: "\(ids.count) read in the background") }
        }
    }

    private func checked(_ id: UUID, _ facts: TextFacts, _ stamp: TextIndex.Stamp?) {
        // Saved meanwhile: the index already has newer facts.
        guard index[id] == nil else { return }
        if let box = boxes[id] {
            // Opened meanwhile: the text in memory is the newest.
            remember(box.text, id)
        } else if let stamp {
            index[id] = TextIndex.Entry(facts: facts, stamp: stamp)
            noFile.remove(id)
        } else {
            noFile.insert(id)
        }
        factsChanged += 1
        saveIndexSoon()
        Transcriber.shared.textChecked(id)
    }

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
        // Only "words still being worked out" changed: the lines didn't.
        if !out.finals.isEmpty || !out.fixes.isEmpty { put(t, id) }
        if run == generation, let v = out.volatile { volatile = v }
        if Date().timeIntervalSince(lastSave) > 10 { save(id) }
    }

    fileprivate func setCatchingUp(_ on: Bool, run: Int) {
        guard run == generation, catchingUp != on else { return }
        catchingUp = on
    }

    fileprivate func save(_ id: UUID) {
        guard let t = texts[id], !t.lines.isEmpty else { return }
        write(t, id, background: true)
        lastSave = Date()
    }

    fileprivate func finished(_ id: UUID, run: Int) {
        save(id)
        guard run == generation else { return }
        activeID = nil
        status = nil
        volatile = ""
        catchingUp = false
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

    /// Most audio handed to the models in one go (5 s). Normally each step
    /// is just the last few hundredths of a second; this only matters when
    /// catching up, so text still comes in steps instead of one big jump.
    static let biggestBite = 5 * 16_000

    /// What one run keeps track of between bits of audio.
    private struct RunState {
        let id: UUID
        let run: Int
        var position: Int64
        var engine: (any LiveEngine)?
        var name = ""
        var offset = 0.0
        var nextTry: Int64 = 0
        var catchingUp = false
        var firstWords = false
    }

    /// Loads Parakeet (with the word list) and the speaker model ahead of
    /// Record. `run` finds them loaded and starts at once.
    func warm() async {
        if await MainActor.run(body: { LiveTranscriber.shared.modelState == .ready }) {
            let terms = await MainActor.run { WordList.shared.boostTerms }
            try? await parakeet.warm(for: terms)
        }
        if await MainActor.run(body: { SpeakerModel.shared.isReady }) {
            try? await speakers.load()
        }
    }

    func cool() async {
        await parakeet.unload()
        await speakers.unload()
    }

    func run(id: UUID, run: Int, queue: LiveQueue, position start: Int64) async {
        var state = RunState(id: id, run: run, position: start)

        // Words first. Parakeet and the speaker model load at the same time,
        // so the first words wait for the slower of the two, not for both
        // one after the other (the mic keeps saving audio meanwhile).
        async let speakersReady: Void = startSpeakers(id: id, position: start)
        await pickEngine(&state)
        await speakersReady
        if speakerStart != nil { LiveFeed.shared.mark("speakers listening") }

        for await _ in queue.wakeups {
            while let input = queue.take(max: Self.biggestBite) {
                await handle(input, &state, queue: queue)
            }
        }
        // Stop: whatever was still waiting.
        while let input = queue.take(max: Self.biggestBite) {
            await handle(input, &state, queue: queue)
        }

        if let engine = state.engine {
            if speakerStart != nil { await speakers.finish() }
            await deliver(await engine.end(), &state)
        }
        await parakeet.unload() // free the memory for files waiting to be transcribed
        await speakers.unload()
        speakerStart = nil
        await MainActor.run { LiveTranscriber.shared.finished(id, run: run) }
    }

    private func handle(_ input: LiveInput, _ state: inout RunState, queue: LiveQueue) async {
        switch input {
        case .samples(let samples):
            guard !samples.isEmpty else { return }
            // Speakers first: then it's ahead of the words that need it.
            if speakerStart != nil { await speakers.feed(samples) }
            if state.engine == nil, state.position >= state.nextTry {
                await pickEngine(&state)
            }
            if let engine = state.engine {
                let out = await engine.feed(samples)
                await deliver(out, &state)
            }
            state.position += Int64(samples.count)
            LiveFeed.shared.finished(samples.count)
            await showCatchingUp(queue.waitingSeconds, &state)
        case .flush:
            if let e = state.engine {
                let out = await e.end()
                await deliver(out, &state)
            }
            state.engine = nil
            state.nextTry = 0
            await showCatchingUp(0, &state)
            let id = state.id
            await MainActor.run { LiveTranscriber.shared.save(id) }
        }
    }

    private func pickEngine(_ state: inout RunState) async {
        (state.engine, state.name) = await pick(run: state.run)
        state.offset = Double(state.position) / 16_000
        if state.engine != nil {
            LiveFeed.shared.mark("\(state.name) listening")
        } else {
            // Nothing could listen: look again after 15 s of audio.
            state.nextTry = state.position + 15 * 16_000
        }
    }

    /// "Catching up" shows above the transcript while more than 4 s of audio
    /// waits, and goes once it's under 1 s (so it doesn't flicker).
    private func showCatchingUp(_ waiting: Double, _ state: inout RunState) async {
        let on = state.catchingUp ? waiting > 1 : waiting > 4
        guard on != state.catchingUp else { return }
        state.catchingUp = on
        let run = state.run
        await MainActor.run { LiveTranscriber.shared.setCatchingUp(on, run: run) }
    }

    private func deliver(_ out: LiveOutput, _ state: inout RunState) async {
        if !state.firstWords, !out.finals.isEmpty {
            state.firstWords = true
            LiveFeed.shared.mark("first words")
        }
        await deliver(out, offset: state.offset, engine: state.name, id: state.id, run: state.run)
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
