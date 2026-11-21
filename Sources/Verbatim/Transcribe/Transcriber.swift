import Foundation
import Observation

/// Read-only access to the old Whisper transcripts: `transcriber.transcripts[id]`.
@MainActor
struct OldTranscripts {
    fileprivate let owner: Transcriber
    subscript(id: UUID) -> Transcript? { owner.old(id) }
}

/// Turns audio files into text with Parakeet (step 5c: Whisper is gone).
/// Used for imported files, "Transcribe again", and recordings made while
/// Parakeet wasn't ready. Recordings made with Parakeet need nothing: their
/// live text is the transcript.
///
/// One file at a time, fed to the same streaming model as live text at full
/// speed (about a minute per hour of audio). It waits while recording, so only
/// one copy of the model is in memory (8 GB Mac). Text goes into live.json as
/// it goes; progress is saved, so Cancel and crashes keep what was done.
@MainActor
@Observable
final class Transcriber {
    static let shared = Transcriber()

    struct Job: Equatable {
        var id: UUID
        var doneSeconds: Double
        var totalSeconds: Double
        var secondsLeft: Double?
        /// Only finding who spoke (the text is already there).
        var speakersOnly = false
    }

    /// Audio handed to the model at a time. Progress is saved after each.
    static let pieceSeconds: Int64 = 30

    private(set) var queue: [UUID] = []
    /// Recordings with text but no speakers yet, for the speaker model to go
    /// over (step 7). Done after the files in `queue`.
    private(set) var speakerQueue: [UUID] = []
    private(set) var active: Job?
    private(set) var importing: Set<UUID> = []
    /// How far the copy of each file being imported is, 0 to 1 (UX round 2, A6).
    private(set) var importProgress: [UUID: Double] = [:]
    /// Old Whisper transcripts (transcript.json), from before step 5c, read
    /// as `transcripts[id]`. Read from disk the first time they're asked for.
    var transcripts: OldTranscripts { OldTranscripts(owner: self) }
    /// Goes up when an old transcript changes (rare: only old recordings).
    private var oldChanged = 0
    /// .some(nil) = there is no transcript.json.
    @ObservationIgnored private var oldCache: [UUID: Transcript?] = [:]
    private(set) var errors: [UUID: String] = [:]
    /// Recordings still getting audio (recording, paused, or in the 10 s Undo
    /// Stop window). Files wait while there is one.
    private(set) var growing: Set<UUID> = []

    @ObservationIgnored private let engine = ParakeetEngine()
    @ObservationIgnored private let speakers = SpeakerEngine()
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested: Set<UUID> = []
    /// Files where the speech model just failed once: one more failure in a
    /// row stops the pass with a message (see `transcribe`).
    @ObservationIgnored private var failedOnce: Set<UUID> = []

    private var live: LiveTranscriber { .shared }
    var isModelReady: Bool { live.isModelReady }
    /// Files wait while recording.
    var isWaitingForRecording: Bool { !growing.isEmpty }

    private init() {}

    /// Called once at launch, after LiveTranscriber has read its index. Only
    /// looks at `TextFacts`, never a whole text. Recordings whose facts
    /// aren't known yet come in later through `textChecked`.
    func start(with recordings: [RecordingInfo]) {
        Self.removeWhisperModel()
        for r in recordings.reversed() { pickUp(r) }
        queueSpeakers(recordings)
    }

    /// The facts about this recording's text are known now (checked in the
    /// background after launch).
    func textChecked(_ id: UUID) {
        guard let r = RecorderModel.shared.info(id) else { return }
        pickUp(r)
        if SpeakerModel.shared.isReady, !r.isActive, r.hasAudio, needsSpeakers(id) { findSpeakers(id) }
    }

    /// Picks up anything left unfinished (quit, crash), and old recordings
    /// that never got any text.
    private func pickUp(_ r: RecordingInfo) {
        // A file still being copied in has only half its audio (A6).
        guard !r.isActive, r.hasAudio, !importing.contains(r.id), let facts = live.facts(r.id) else { return }
        if facts.liveUnfinished == true {
            finishLive(r)
        } else if facts.passFinished != nil {
            if facts.passUnfinished, !facts.passStoppedByUser { enqueue(r.id) }
        } else if !facts.hasLines {
            let old = transcripts[r.id]
            if old == nil || (old?.finished == false && old?.stoppedByUser == false) { enqueue(r.id) }
        }
    }

    /// Live text never got to the end of the audio (crash, force quit, Stop
    /// and Quit while it was behind). Hunt 1 bug 3: the end of the class
    /// used to stay missing unless Ryan pressed Transcribe again. Now
    /// Parakeet goes over the audio after the last line, and only that.
    /// Text from the Mac's backup engine is redone whole, like after a
    /// normal Stop, once Parakeet is here (until then the Mac's text stays).
    /// So is text where the live model failed on some of the audio.
    private func finishLive(_ r: RecordingInfo) {
        guard var text = live.texts[r.id] else { return }
        if text.madeWithBackupEngine || text.missedAudio == true {
            if isModelReady { redo(r.id) }
            return
        }
        // Where live text got to. Lines Ryan deleted at the end count too.
        let from = max(text.lines.map(\.end).max() ?? 0, text.removed?.map(\.end).max() ?? 0)
        text.liveUnfinished = nil
        let left = from < r.duration - 2
        if left { text.pass = LiveText.FilePass(doneUpTo: from) }
        live.setText(text, for: r.id)
        if left { enqueue(r.id) }
    }

    /// The speaker model finished downloading: label what's already there.
    func speakerModelReady() {
        queueSpeakers(RecorderModel.shared.recordings)
    }

    /// Recordings that have text but no speakers yet (made before step 7, or
    /// before the speaker model was here) get speakers found by themselves.
    private func queueSpeakers(_ recordings: [RecordingInfo]) {
        guard SpeakerModel.shared.isReady else { return }
        for r in recordings.reversed() where !r.isActive && r.hasAudio && needsSpeakers(r.id) {
            findSpeakers(r.id)
        }
    }

    private func needsSpeakers(_ id: UUID) -> Bool {
        guard let f = live.facts(id), !f.speakersFound, f.hasLines else { return false }
        if f.passUnfinished { return false } // gets them while being transcribed
        return !f.hasVoices
    }

    /// Goes over the file with the speaker model only, keeping the text. Also
    /// "Find speakers again" in the More menu, if the labels came out wrong.
    func findSpeakers(_ id: UUID) {
        guard !speakerQueue.contains(id), active?.id != id else { return }
        errors[id] = nil
        speakerQueue.append(id)
        runQueue()
    }

    func isFindingSpeakers(_ id: UUID) -> Bool {
        speakerQueue.contains(id) || (active?.id == id && active?.speakersOnly == true)
    }

    /// Parakeet finished downloading: start anything that was waiting.
    func modelReady() { runQueue() }

    // MARK: - Queue

    /// Starts or continues going over the file.
    func enqueue(_ id: UUID) {
        errors[id] = nil
        var text = live.texts[id] ?? LiveText()
        if text.pass == nil {
            // Carry on after an unfinished old Whisper transcript, if there is one.
            let old = transcripts[id]
            text.pass = LiveText.FilePass(doneUpTo: old?.finished == false ? old?.doneUpTo ?? 0 : 0)
        }
        text.pass?.stoppedByUser = false
        live.setText(text, for: id)
        guard !queue.contains(id) else { return }
        queue.append(id)
        runQueue()
    }

    /// Does the whole file again with Parakeet. Ryan's edited lines and deleted
    /// lines in the live text are kept (old Whisper text is dropped).
    func redo(_ id: UUID) {
        guard active?.id != id, !growing.contains(id) else { return }
        queue.removeAll { $0 == id }
        speakerQueue.removeAll { $0 == id } // the new pass finds speakers as it goes
        try? FileManager.default.removeItem(at: TranscriptStore.url(id))
        setOld(nil, id)
        let old = live.texts[id]
        // Edited lines are kept with the speaker they show now (their voice
        // numbers mean nothing to the new pass).
        let labels = Speakers.Labeler(old)
        let edited = (old?.lines ?? []).filter(\.isLocked).map { line in
            var l = line
            // A real name stays; "Speaker 2" would mean someone else in the new pass.
            let name = labels.name(line)
            l.speaker = name?.hasPrefix("Speaker ") == true ? nil : name
            l.voice = nil
            return l
        }
        var fresh = LiveText(pass: LiveText.FilePass(keep: edited.isEmpty ? nil : edited))
        fresh.removed = old?.removed
        fresh.voiceSessions = old?.voiceSessions
        live.setText(fresh, for: id)
        enqueue(id)
    }

    func cancel(_ id: UUID) {
        if active?.id == id { cancelRequested.insert(id) }
        queue.removeAll { $0 == id }
        if speakerQueue.contains(id) || (active?.id == id && active?.speakersOnly == true) {
            speakerQueue.removeAll { $0 == id }
            live.markSpeakersFound(id) // Ryan said no: don't start it again by itself
        }
        if var text = live.texts[id], var pass = text.pass, !pass.finished {
            pass.stoppedByUser = true
            text.pass = pass
            live.setText(text, for: id)
        }
    }

    /// The recording was moved to the Trash.
    func forget(_ id: UUID) {
        if active?.id == id { cancelRequested.insert(id) }
        queue.removeAll { $0 == id }
        speakerQueue.removeAll { $0 == id }
        growing.remove(id)
        oldCache[id] = nil // read again if it's put back
        oldChanged += 1
        errors[id] = nil
    }

    func reload(_ id: UUID) {
        setOld(TranscriptStore.load(id), id)
    }

    func setImporting(_ id: UUID, _ on: Bool) {
        if on {
            importing.insert(id)
            importProgress[id] = 0
        } else {
            importing.remove(id)
            importProgress[id] = nil
        }
    }

    func setImportProgress(_ id: UUID, _ fraction: Double) {
        guard importing.contains(id) else { return }
        importProgress[id] = fraction
    }

    func isQueued(_ id: UUID) -> Bool { queue.contains(id) }

    func isGrowing(_ id: UUID) -> Bool { growing.contains(id) }

    /// The file is still being gone over (queued, running, or stopped halfway).
    func isUnfinished(_ id: UUID) -> Bool {
        live.facts(id)?.passUnfinished ?? false
    }

    // MARK: - While recording

    /// Recording started, or carried on after Undo Stop. Files wait.
    func recordingStarted(_ id: UUID) {
        growing.insert(id)
    }

    /// Stopped for good (Undo Stop expired). If live text came from the Mac's
    /// backup engine, nobody listened, or the live model failed on some of
    /// the audio, redo it with Parakeet by itself (edits kept). If Parakeet
    /// isn't here yet, the transcript offers it later.
    /// No text at all and Parakeet still coming: it waits in the queue and
    /// starts once the download is done (UX round 2, A10: it used to wait for
    /// a relaunch, though the page said text comes after Stop).
    func recordingFinal(_ id: UUID) {
        growing.remove(id)
        let text = live.texts[id]
        let empty = text?.lines.isEmpty ?? true
        if isModelReady, text?.pass == nil, empty || text?.needsRedo == true {
            redo(id)
        } else if !isModelReady, text?.pass == nil, empty,
                  RecorderModel.shared.info(id)?.hasAudio == true {
            enqueue(id)
        } else if SpeakerModel.shared.isReady, needsSpeakers(id) {
            findSpeakers(id)
        }
        runQueue()
        AudioSquash.shared.run()
    }

    // MARK: - Editing old Whisper lines

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

    /// Undo of Transcribe again: the old Whisper transcript comes back as it was.
    func putBackOld(_ t: Transcript, _ id: UUID) {
        commit(t, id)
    }

    private func commit(_ t: Transcript, _ id: UUID) {
        setOld(t, id)
        try? TranscriptStore.save(t, for: id)
    }

    private func setOld(_ t: Transcript?, _ id: UUID) {
        oldCache[id] = .some(t)
        oldChanged += 1
    }

    fileprivate func old(_ id: UUID) -> Transcript? {
        _ = oldChanged // watch for changes
        if let cached = oldCache[id] { return cached }
        // First time: read it now (not a change anyone needs to hear about).
        let t = TranscriptStore.load(id)
        oldCache[id] = .some(t)
        return t
    }

    // MARK: - Running

    /// No file being transcribed or waiting (the live models may load then).
    var isIdle: Bool { workTask == nil && queue.isEmpty }

    /// Record was pressed while a file was being transcribed: the file stops
    /// at its next piece and frees its models. Live text waits for that, so
    /// the file's Parakeet and the live one are never loaded at once (8 GB).
    /// The mic keeps saving audio meanwhile; live text catches up.
    func modelsFreed() async {
        while let task = workTask {
            await task.value
            if workTask == task { break }
        }
    }

    private func runQueue() {
        let files = isModelReady && !queue.isEmpty
        let voices = SpeakerModel.shared.isReady && !speakerQueue.isEmpty
        guard workTask == nil, growing.isEmpty, files || voices else { return }
        workTask = Task {
            // The live models loaded ahead of Record go first: one Parakeet at a time.
            await live.coolDown()
            while isModelReady, let id = queue.first, growing.isEmpty {
                let finished = await transcribe(id)
                if finished {
                    queue.removeAll { $0 == id }
                    fileDone(id)
                }
            }
            await engine.unload() // free the memory until the next file
            while queue.isEmpty, SpeakerModel.shared.isReady, let id = speakerQueue.first, growing.isEmpty {
                let finished = await speakersOnly(id)
                if finished { speakerQueue.removeAll { $0 == id } }
            }
            await speakers.unload()
            workTask = nil
            runQueue()
            // Done with files and the start page is open: load the live
            // models again, ready for Record.
            let model = RecorderModel.shared
            if workTask == nil, model.selection == nil, !model.showingDeleted { live.warmUp() }
            AudioSquash.shared.run() // shrink the audio of files that are done
        }
    }

    /// A file finished (step 10): a banner if you're not looking, then a name.
    private func fileDone(_ id: UUID) {
        guard live.texts[id]?.pass?.finished == true, let info = RecorderModel.shared.info(id) else { return }
        if info.importedFrom != nil {
            Messages.shared.post(Messages.memoDone(info.title, lines: live.texts[id]?.lines.count ?? 0))
        }
        AutoName.shared.consider(id)
    }

    /// Goes over one file from where it was left. Returns true when it is done
    /// with it (finished, cancelled or failed), false when it stopped for a
    /// recording and should carry on later.
    private func transcribe(_ id: UUID) async -> Bool {
        let audio = RecordingStore.audioURL(id)
        guard FileManager.default.fileExists(atPath: audio.path),
              let pass = live.texts[id]?.pass, !pass.finished else { return true }
        cancelRequested.remove(id)

        // WAV or the squashed m4a. Opened once, so squashing can't pull it away.
        let reader: AudioReader
        do {
            reader = try AudioReader(audio)
        } catch {
            errors[id] = "Couldn't open the audio: \(error.localizedDescription)"
            return true
        }
        let rate = reader.rate
        let total = reader.length
        var pos = min(Int64(pass.doneUpTo * rate), total)
        active = Job(id: id, doneSeconds: Double(pos) / rate, totalSeconds: Double(total) / rate)
        defer {
            cancelRequested.remove(id)
            active = nil
        }

        do {
            try await engine.begin()
        } catch {
            errors[id] = "Couldn't load the speech model: \(error.localizedDescription)"
            return true
        }
        // Speakers as it goes, if the speaker model is here. Without it the
        // text still comes; speakers are found afterwards.
        var voiceBase: Int?
        if SpeakerModel.shared.isReady {
            do {
                let names = try await speakers.begin(known: VoiceLibrary.shared.knownVoices())
                voiceBase = live.newVoiceSession(id, names: names)
            } catch {
                await speakers.unload()
                SpeakerModel.shared.broken()
            }
        }

        let offset = Double(pos) / rate
        let started = Date()
        let startPos = pos
        while pos < total {
            if cancelRequested.contains(id) || !growing.isEmpty {
                // Finish the words heard so far, so it can carry on cleanly from here.
                let out = await engine.end()
                if voiceBase != nil { await speakers.finish() }
                let words = await voiced(out.finals, voiceBase)
                live.addPass(words, fixes: out.fixes, offset: offset, to: id, doneUpTo: Double(pos) / rate, finished: false)
                return cancelRequested.contains(id)
            }
            let end = min(pos + Self.pieceSeconds * Int64(rate), total)
            let samples: [Float]
            do {
                samples = try reader.samples(from: pos, count: end - pos)
            } catch {
                errors[id] = "Transcribing stopped: \(error.localizedDescription)"
                return true
            }
            if voiceBase != nil { await speakers.feed(samples) }
            let out: LiveOutput
            do {
                out = try await engine.feed(samples)
            } catch {
                // Never carry on with a hole in the text (code health item 4).
                // Progress is saved up to the last word, so it can go on from
                // there: once by itself with Parakeet loaded fresh, then by
                // "Try again".
                LiveFeed.shared.noteError("Parakeet, file at \(Int(Double(pos) / rate / 60)) min: \(error.localizedDescription)")
                if voiceBase != nil { await speakers.finish() }
                await engine.unload()
                if failedOnce.insert(id).inserted { return false }
                failedOnce.remove(id)
                errors[id] = "Transcribing stopped at \(Int(Double(pos) / rate / 60)) min: the speech model ran into a problem."
                return true
            }
            failedOnce.remove(id)
            pos = end
            // Words come out a couple of seconds behind the audio, so after a
            // crash it carries on from the last word that made it into the text.
            let lastWord = out.finals.last.map { $0.end + offset }
            let words = await voiced(out.finals, voiceBase)
            live.addPass(words, fixes: out.fixes, offset: offset, to: id, doneUpTo: lastWord, finished: false)

            let done = Double(pos - startPos)
            let elapsed = Date().timeIntervalSince(started)
            active = Job(
                id: id,
                doneSeconds: Double(pos) / rate,
                totalSeconds: Double(total) / rate,
                secondsLeft: done > 0 ? elapsed / done * Double(total - pos) : nil
            )
            await Task.yield()
        }
        if voiceBase != nil { await speakers.finish() }
        let out = await engine.end()
        let words = await voiced(out.finals, voiceBase)
        live.addPass(words, fixes: out.fixes, offset: offset, to: id, doneUpTo: Double(total) / rate, finished: true)
        if voiceBase != nil { live.markSpeakersFound(id) }
        return true
    }

    /// Words get voices. The speaker model started at the same place in the
    /// file as Parakeet, so their times line up.
    private func voiced(_ words: [LivePiece], _ base: Int?) async -> [LivePiece] {
        guard let base, !words.isEmpty else { return words }
        return await speakers.label(words, shift: 0, base: base)
    }

    /// The speaker model goes over the whole file, then the lines get voices
    /// (split where the voice changes). The text itself doesn't change.
    /// Returns false when it stopped for a recording and should start again later.
    private func speakersOnly(_ id: UUID) async -> Bool {
        let audio = RecordingStore.audioURL(id)
        guard FileManager.default.fileExists(atPath: audio.path), live.texts[id] != nil else { return true }
        cancelRequested.remove(id)
        let reader: AudioReader
        do {
            reader = try AudioReader(audio)
        } catch {
            live.markSpeakersFound(id)
            return true
        }
        let rate = reader.rate
        let total = reader.length
        active = Job(id: id, doneSeconds: 0, totalSeconds: Double(total) / rate, speakersOnly: true)
        defer {
            cancelRequested.remove(id)
            active = nil
        }
        let names: [Int: String]
        do {
            names = try await speakers.begin(known: VoiceLibrary.shared.knownVoices())
        } catch {
            await speakers.unload()
            SpeakerModel.shared.broken()
            return false
        }
        var pos: Int64 = 0
        let started = Date()
        while pos < total {
            if cancelRequested.contains(id) { return true }
            if !growing.isEmpty { return false } // starts over after the recording
            let end = min(pos + Self.pieceSeconds * Int64(rate), total)
            guard let samples = try? reader.samples(from: pos, count: end - pos) else {
                live.markSpeakersFound(id)
                return true
            }
            await speakers.feed(samples)
            pos = end
            let elapsed = Date().timeIntervalSince(started)
            active = Job(
                id: id,
                doneSeconds: Double(pos) / rate,
                totalSeconds: Double(total) / rate,
                secondsLeft: pos > 0 ? elapsed / Double(pos) * Double(total - pos) : nil,
                speakersOnly: true
            )
            await Task.yield()
        }
        await speakers.finish()
        let frames = await speakers.frames
        live.applyVoices(id, frames: frames, base: live.newVoiceSession(id), names: names)
        return true
    }

    /// The Whisper model from before step 5c (626 MB): deleted once so Ryan
    /// gets the space back. Everything in Models except Parakeet's folder.
    private static func removeWhisperModel() {
        let key = "whisperModelRemoved"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let models = support.appending(path: "Verbatim/Models", directoryHint: .isDirectory)
        let keep = ParakeetEngine.base.standardizedFileURL.lastPathComponent // "Live"
        let items = (try? FileManager.default.contentsOfDirectory(at: models, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent != keep {
            try? FileManager.default.removeItem(at: item)
        }
        for old in ["modelFolder", "modelPrepared"] { UserDefaults.standard.removeObject(forKey: old) }
        UserDefaults.standard.set(true, forKey: key)
    }
}

extension Transcriber {
    /// "about 4 min left"
    nonisolated static func leftText(_ seconds: Double) -> String {
        if seconds < 60 { return "under a minute left" }
        return "about \(Int((seconds / 60).rounded())) min left"
    }
}
