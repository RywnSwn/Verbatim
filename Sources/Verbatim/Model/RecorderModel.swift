import AVFoundation
import AppKit
import Observation
import UniformTypeIdentifiers

/// The app's recording state. One recording at a time.
@MainActor
@Observable
final class RecorderModel {
    static let shared = RecorderModel()

    enum Phase { case idle, recording, paused }

    /// What the status spot in the bottom bar says. `action` adds a text link.
    struct Status: Equatable {
        enum Action { case stopRecording, resume, undoDelete, undoLine, showFile, undoAudioDelete, changeVoice, openMicSettings }
        var text: String
        var action: Action?
        var id = UUID()
        /// True while it stays true (battery low, chosen mic missing, quiet,
        /// disk almost full, paused for a problem). A short message only
        /// covers it for a moment; then it comes back (B1).
        var standing = false
    }

    /// Shown for 10 s after Stop, with Undo Stop.
    struct StoppedNote: Equatable {
        var recordingID: UUID
        var text: String
        /// `undoSerial` when it stopped: ⌘Z does Undo Stop only if nothing
        /// with its own Undo happened since (UX round 2, A4).
        var serial = 0
    }

    static let barCount = 40
    static let maxLength: TimeInterval = 3 * 3600
    /// Settings > General: how many quiet minutes before "Still recording?"
    /// (step 10, Ryan picked 5). 0 = never ask.
    static let quietMinutesKey = "quietMinutes"
    static var quietMinutes: Int {
        UserDefaults.standard.object(forKey: quietMinutesKey) as? Int ?? 5
    }
    /// While recording: audio.wav (16 kHz) plus listen.wav (48 kHz), 16-bit.
    static let bytesPerHour: Int64 = (16_000 + 48_000) * 2 * 3600

    /// Undo Stop: the listening copy carries on too, padded with silence if
    /// it's short, so it stays in step with audio.wav. None if the recording
    /// never had one.
    static func listenWriter(appendingTo id: UUID, after samples: Int64) -> WavWriter? {
        let url = RecordingStore.listenWavURL(id)
        guard FileManager.default.fileExists(atPath: url.path),
              let w = try? WavWriter(appendingTo: url, rate: WavWriter.listenRate) else { return nil }
        try? w.pad(to: samples * Int64(WavWriter.listenRate / WavWriter.sampleRate))
        return w
    }

    private(set) var phase: Phase = .idle
    private(set) var recordings: [RecordingInfo] = []
    private(set) var currentID: UUID?
    var selection: UUID? {
        didSet {
            if fixOffer?.recordingID != selection { fixOffer = nil }
            if selection != nil { showingDeleted = false }
        }
    }
    /// Step 8: after a word fix, the line under it asks to remember it.
    struct FixOffer: Equatable {
        var recordingID: UUID
        var start: Double
        var fix: PhraseFix
    }

    var fixOffer: FixOffer?
    /// Set by ⇧⌘N: the transcript starts typing a note on that line, then clears it.
    var noteRequest: NoteRequest?
    /// The Marker or Note tool picked in the toolbar: clicking a line puts a
    /// marker or a note there. nil = no tool, a click just picks the line.
    var lineTool: LineTool?
    /// The main area shows Recently deleted (step 9).
    var showingDeleted = false
    private(set) var levels: [Float] = Array(repeating: 0, count: RecorderModel.barCount)
    private(set) var elapsed: TimeInterval = 0
    /// The timer in the menu bar. Changes once a second (not 20 times, like
    /// `elapsed`): the menu bar item lives outside the app's own window, so
    /// every change is a round trip to macOS.
    private(set) var menuClock = "00:00"
    private(set) var status: Status? {
        didSet {
            guard status?.id != oldValue?.id else { return }
            if status?.standing == true {
                warning = nil
                return
            }
            // A short message pushed a warning aside: keep it for later.
            if let old = oldValue, old.standing, status != nil { warning = old }
            // The short message is gone: the warning comes back.
            if status == nil, isBusy, let w = warning {
                warning = nil
                status = w
            }
        }
    }
    /// A standing warning covered by a short message (see `Status.standing`).
    @ObservationIgnored private var warning: Status?

    /// The warning is no longer true: gone from view and from memory.
    private func clearStanding(_ match: (Status) -> Bool) {
        if let w = warning, match(w) { warning = nil }
        if let s = status, match(s) { status = nil }
    }
    /// Recordings whose last change couldn't be saved (see `persist`).
    @ObservationIgnored private var unsaved: Set<UUID> = []
    private(set) var stoppedNote: StoppedNote?
    /// Shown for 10 s after Move to Trash, with Undo.
    struct DeletedNote: Equatable {
        var info: RecordingInfo
        var trashURL: URL
        var id = UUID()
        /// Its step on the ⌘Z list, taken off when the Undo link is used.
        var step: UUID?
    }

    private(set) var deletedNote: DeletedNote?
    var recoveryNotice: String?

    /// "Copied 58 lines" on the Copy button for a moment (step 6).
    struct CopyFeedback: Equatable {
        var text: String
        var id = UUID()
    }

    var copyFeedback: CopyFeedback? {
        didSet {
            guard let note = copyFeedback else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.8))
                if self?.copyFeedback == note { self?.copyFeedback = nil }
            }
        }
    }

    /// Search in the transcript on screen. Cleared when another recording is picked.
    var searchText = "" {
        didSet { if searchText != oldValue { matchIndex = 0; matchJump += 1 } }
    }
    /// Which hit is the current one (0 based).
    var matchIndex = 0
    /// Goes up each time the view should scroll to the current hit.
    var matchJump = 0
    /// Goes up when Cmd+F is pressed, so the view focuses the search field.
    private(set) var findRequest = 0

    func requestFind() { findRequest += 1 }
    /// The ⌘K menu (step 10).
    var showCommandMenu = false
    /// A group to rename in the sidebar (a new one gets named right away).
    var renameGroupRequest: UUID?
    /// Goes up on every click on a sidebar recording, even the one already
    /// open, so the floating sidebar closes then too (C5).
    var sidebarPicks = 0
    /// Takes back a group just made by New Group… if its name box is cancelled.
    @ObservationIgnored var newGroupCancel: (() -> Void)?
    private(set) var micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var micName = "MacBook mic"

    @ObservationIgnored private let pipeline = AudioPipeline()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastLoud = Date()
    @ObservationIgnored private var quietWarned = false
    /// Asks "Still paused?" after `pausedAskMinutes` (A9).
    @ObservationIgnored private var pausedCheck: Task<Void, Never>?
    static let pausedAskMinutes = 15
    @ObservationIgnored private var lastBatteryCheck = Date.distantPast
    @ObservationIgnored private var batteryWarned = false
    /// "10 minutes left" was said for this recording.
    @ObservationIgnored private var limitWarned = false
    @ObservationIgnored private var asleepSince: Date?
    @ObservationIgnored private var restartedAfterError = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Every change with Undo (line edits, deletes, markers, notes, speakers,
    /// moves), newest last. ⌘Z takes them back one by one, also after the
    /// Undo link in the bottom bar has gone (Ryan, 2026-11-19).
    ///
    /// Each step knows its recording (UX round 2, A4): ⌘Z only undoes steps
    /// of the recording on screen (or the one recording now), and steps
    /// with no recording (group delete, moves, recording deletes). A step
    /// whose recording is in Recently deleted waits until it's put back.
    @ObservationIgnored private var undoStack: [UndoStep] = []
    /// Goes up with every new step, so Undo Stop knows if something newer came.
    @ObservationIgnored private var undoSerial = 0

    private struct UndoStep {
        var id = UUID()
        var text: String
        var recording: UUID?
        /// A recording delete: the recording it puts back. Only undoable
        /// while that recording is still in Recently deleted.
        var restores: UUID?
        var run: () -> Void
    }
    @ObservationIgnored private var fileToShow: URL?
    /// Files being copied in (Voice Memo import), for Cancel.
    @ObservationIgnored private var importTasks: [UUID: Task<Void, Never>] = [:]
    /// What the text link in the status spot does, for `offer`.
    @ObservationIgnored private var offered: (() -> Void)?
    /// Delete Audio Only, for Undo: which recording and where its audio went in the Trash.
    /// Delete Audio's Undo: each file moved to the Trash, and where it was.
    @ObservationIgnored private var audioUndo: (id: UUID, files: [(trash: URL, original: URL)])?

    var current: RecordingInfo? { recordings.first { $0.id == currentID } }
    var isBusy: Bool { phase != .idle }

    private init() {
        let began = Date()
        var all = RecordingStore.loadAll()
        recoverUnfinished(&all)
        let halfImported = recoverImports(&all)
        recordings = all
        refreshMicName()
        wirePipeline()
        observeSystem()
        LiveTranscriber.shared.start(with: recordings) // loads the texts Transcriber looks at
        Transcriber.shared.start(with: recordings)
        // After init: AudioSquash looks at RecorderModel.shared.
        Task { @MainActor in
            for (id, url) in halfImported { RecorderModel.shared.runImport(id, from: url, access: false) }
            AudioSquash.shared.run()
            AudioCleanup.start()
        }
        LaunchTimer.shared.mark("recordings read", detail: String(format: "%ld recordings, %.3f s on the main thread", recordings.count, Date().timeIntervalSince(began)))
    }

    // MARK: - Start / Pause / Stop

    func toggleRecording() {
        if isBusy { stop() } else { Task { await start() } }
    }

    func togglePause() {
        switch phase {
        case .recording: pause()
        case .paused: resume()
        case .idle: break
        }
    }

    /// "New recording": show the start screen, or the recording in progress.
    /// Never starts recording by itself (Ryan's ask): only the start screen's
    /// Start button, ⌘R, the menu bar and ⌘K start one. With a group (the
    /// "+" next to a group name), "Save in" is set to that group, like
    /// "New chat" in a Claude project.
    func showNewRecording(in groupID: UUID? = nil, pickGroup: Bool = false) {
        // Recently deleted covers the start screen, so New recording looked
        // like it did nothing from there.
        showingDeleted = false
        if isBusy {
            selection = currentID
            return
        }
        if pickGroup { GroupStore.shared.lastUsedID = GroupStore.shared.group(groupID)?.id }
        selection = nil
    }

    /// Starts in the group picked last time (start screen, ⌘R, menu bar).
    func start() async {
        await start(in: GroupStore.shared.lastUsedID)
    }

    /// Starts a recording in a group (nil = Recents). It's named after the day,
    /// since the group already says which class; auto-naming may give it a
    /// better name after Stop.
    func start(in groupID: UUID?) async {
        guard phase == .idle else { return }

        if micPermission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        guard micPermission == .authorized, phase == .idle else {
            selection = nil
            // Record from the menu bar or ⌘R used to do nothing at all (A8).
            if micPermission == .denied || micPermission == .restricted {
                status = Status(text: "Verbatim can't hear anything: Microphone access is off.", action: .openMicSettings)
            }
            return
        }
        // The mic would pick up the speakers.
        Playback.shared.close()

        let (dev, fellBack) = Microphones.resolve()
        guard let dev else {
            status = Status(text: "No microphone found. Plug one in, then press Start again.")
            return
        }

        let now = Date()
        let group = GroupStore.shared.group(groupID)?.id
        GroupStore.shared.lastUsedID = group
        var info = RecordingInfo(id: UUID(), title: Self.dayTitle(now), createdAt: now, state: .recording)
        info.groupID = group
        info.autoTitle = true
        info.events.append(.init(kind: .started, at: now, sample: 0, note: Microphones.mic(for: dev).displayName))
        do {
            try RecordingStore.create(info)
            let writer = try WavWriter(creating: RecordingStore.wavURL(info.id))
            let listen = try? WavWriter(creating: RecordingStore.listenWavURL(info.id), rate: WavWriter.listenRate)
            pipeline.attach(writer, listen: listen)
            LiveTranscriber.shared.recordingStarted(info.id, samples: 0)
            try pipeline.startCapture(device: dev)
            Transcriber.shared.recordingStarted(info.id)
        } catch {
            pipeline.detach()
            LiveTranscriber.shared.recordingStopped()
            // Nothing was recorded: no 0 min recording left behind, and no
            // "Verbatim quit during…" at next launch (B3).
            LiveTranscriber.shared.forget(info.id)
            try? FileManager.default.removeItem(at: RecordingStore.folder(info.id))
            status = Status(text: "Couldn't start recording: \(error.localizedDescription) Try again, or pick another mic in Settings > General.")
            return
        }

        // Undo Stop is over for the recording stopped a moment ago: let its
        // background work start now (it used to wait for a timer that a
        // new recording cancelled, so it stalled until relaunch).
        finishStopped()
        deletedNote = nil
        device = dev
        refreshMicName()
        recordings.insert(info, at: 0)
        currentID = info.id
        selection = info.id
        elapsed = 0
        levels = Array(repeating: 0, count: Self.barCount)
        lastLoud = Date()
        quietWarned = false
        batteryWarned = false
        limitWarned = false
        lastBatteryCheck = .distantPast
        phase = .recording
        beginKeepAwake()

        if fellBack {
            status = Status(text: "Your chosen mic isn't plugged in. Using the MacBook mic.", standing: true)
        } else if let free = RecordingStore.freeSpace(), free < Self.bytesPerHour * 3 {
            let hours = Double(free) / Double(Self.bytesPerHour)
            status = Status(text: String(format: "Disk is almost full: room for about %.1f hours of audio.", hours), standing: true)
        } else {
            status = nil
        }
    }

    func pause() {
        guard phase == .recording else { return }
        pipeline.stopCapture()
        pipeline.flush()
        LiveTranscriber.shared.micStopped()
        addEvent(.paused)
        updateCurrent { $0.state = .paused }
        phase = .paused
        levels = Array(repeating: 0, count: Self.barCount)
        saveCurrent()
        clearStanding { $0.action == .stopRecording }
        Messages.shared.withdraw("stillRecording")
        // Nothing is being recorded, so the Mac may sleep (A9: it used to stay
        // awake all night when Pause was forgotten). Sleeping while paused
        // loses nothing; Resume starts the mic again.
        endKeepAwake()
        askIfStillPaused()
    }

    /// Paused and forgotten: ask once, after 15 minutes, like "Still
    /// recording?" (off when that is off in Settings).
    private func askIfStillPaused() {
        pausedCheck?.cancel()
        guard Self.quietMinutes > 0, let id = currentID else { return }
        pausedCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(Self.pausedAskMinutes) * 60))
            guard !Task.isCancelled, let self, self.phase == .paused, self.currentID == id else { return }
            // A pause for a problem keeps its reason and Resume link.
            if self.status?.action != .resume, self.warning?.action != .resume {
                self.status = Status(text: "Paused for \(Self.pausedAskMinutes) minutes. Class over?", action: .stopRecording, standing: true)
            }
            Messages.shared.post(Messages.stillPaused(minutes: Self.pausedAskMinutes, elapsed: self.elapsed))
        }
    }

    func resume() {
        guard phase == .paused else { return }
        let (dev, fellBack) = Microphones.resolve()
        guard let dev else {
            status = Status(text: "No microphone found. Plug one in, then press Resume.")
            return
        }
        if pipeline.hasWriteError {
            // Paused because the disk was full: only go on once there's room
            // and the file is fixed, or nothing would be saved.
            let stillFull = (RecordingStore.freeSpace() ?? .max) < Self.bytesPerHour / 6
            if stillFull || !pipeline.clearWriteError() {
                status = Status(text: stillFull
                    ? "The disk is still full. Free up space, then"
                    : "Can't save audio to the disk. Free up space, then", action: .resume, standing: true)
                return
            }
        }
        do {
            try pipeline.startCapture(device: dev)
        } catch {
            status = Status(text: "Couldn't use the mic: \(error.localizedDescription)", action: .resume, standing: true)
            return
        }
        device = dev
        refreshMicName()
        addEvent(.resumed)
        updateCurrent { $0.state = .recording }
        phase = .recording
        pausedCheck?.cancel()
        pausedCheck = nil
        Messages.shared.withdraw("stillRecording")
        beginKeepAwake()
        lastLoud = Date()
        quietWarned = false
        warning = nil // the reasons for the pause are over
        status = fellBack ? Status(text: "Your chosen mic isn't plugged in. Using the MacBook mic.", standing: true) : nil
        saveCurrent()
    }

    func stop(note: String? = nil) {
        guard isBusy, let id = currentID else { return }
        let samples = pipeline.detach()
        LiveTranscriber.shared.recordingStopped()
        let now = Date()
        updateCurrent {
            $0.samples = samples
            $0.state = .stopped
            $0.endedAt = now
        }
        addEvent(.stopped)
        saveCurrent()
        endKeepAwake()
        pausedCheck?.cancel()
        pausedCheck = nil

        let info = current
        phase = .idle
        currentID = nil
        device = nil
        warning = nil
        status = nil
        levels = Array(repeating: 0, count: Self.barCount)
        Messages.shared.withdraw("stillRecording")
        Messages.shared.withdraw("battery")

        let title = info?.title ?? "Recording"
        let length = Self.minutesText(info?.duration ?? 0)
        let text = note ?? "Saved \(title), \(length)."
        let stopped = StoppedNote(recordingID: id, text: text, serial: undoSerial)
        stoppedNote = stopped
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.stoppedNote == stopped else { return }
            self.finishStopped()
        }
    }

    /// Undo Stop is no longer possible (10 s are over, or a new recording
    /// started), so the stopped recording is final. Files waiting for the
    /// recording to end can start now, and it can get a name.
    private func finishStopped() {
        guard let note = stoppedNote else { return }
        stoppedNote = nil
        Transcriber.shared.recordingFinal(note.recordingID)
        AutoName.shared.consider(note.recordingID)
    }

    /// ⌘Q > Stop and Quit: no Undo Stop in the bar (C10: it showed one, and
    /// pressing it still quit). The bar says it's saving instead.
    func stopForQuit() {
        stop()
        finishStopped()
    }

    /// Continues the recording that was just stopped, in the same audio file.
    func undoStop() {
        guard phase == .idle, let note = stoppedNote,
              let info = recordings.first(where: { $0.id == note.recordingID }) else { return }
        // The mic would pick up the speakers (C10: the player stayed open).
        Playback.shared.close()
        let (dev, fellBack) = Microphones.resolve()
        guard let dev else {
            finishStopped()
            status = Status(text: "No microphone found, so the recording stayed stopped.")
            return
        }
        do {
            let writer = try WavWriter(appendingTo: RecordingStore.wavURL(info.id))
            pipeline.attach(writer, listen: Self.listenWriter(appendingTo: info.id, after: writer.samplesWritten))
            LiveTranscriber.shared.recordingStarted(info.id, samples: writer.samplesWritten)
            try pipeline.startCapture(device: dev)
            Transcriber.shared.recordingStarted(info.id)
        } catch {
            pipeline.detach()
            LiveTranscriber.shared.recordingStopped()
            finishStopped()
            status = Status(text: "Couldn't continue the recording: \(error.localizedDescription)")
            return
        }
        stoppedNote = nil
        currentID = info.id
        selection = info.id
        device = dev
        refreshMicName()
        updateCurrent {
            $0.state = .recording
            $0.endedAt = nil
        }
        addEvent(.undoStop)
        elapsed = info.duration
        lastLoud = Date()
        quietWarned = false
        phase = .recording
        beginKeepAwake()
        warning = nil
        status = fellBack ? Status(text: "Your chosen mic isn't plugged in. Using the MacBook mic.", standing: true) : nil
        saveCurrent()
    }

    func perform(_ action: Status.Action) {
        switch action {
        case .stopRecording: stop()
        case .resume: resume()
        case .undoDelete: undoDelete()
        case .undoLine:
            // The link belongs to the newest step: undo exactly that one.
            if status?.action == .undoLine { status = nil }
            if let i = undoStack.lastIndex(where: { undoable($0) }) {
                let step = undoStack.remove(at: i)
                if let id = deletedNote?.step, id == step.id { deletedNote = nil }
                step.run()
                flash("Undid: \(Self.undoName(step.text))")
            }
        case .showFile:
            if let url = fileToShow { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            status = nil
        case .undoAudioDelete: undoAudioDelete()
        case .openMicSettings:
            status = nil
            openMicSettings()
        case .changeVoice:
            let run = offered
            offered = nil
            if status?.action == .changeVoice { status = nil }
            run?()
        }
    }

    // MARK: - Delete (Move to Trash, with Undo)

    func canDelete(_ id: UUID) -> Bool { id != currentID }

    /// Moves the recording to Recently deleted (step 9): Undo for 10 s, Put
    /// Back for 30 days.
    func delete(_ id: UUID) {
        // Still being copied in: stop the copy instead (A6). It used to go to
        // Recently deleted half done and say "Importing…" forever after Put Back.
        if Transcriber.shared.importing.contains(id) {
            cancelImport(id)
            return
        }
        guard canDelete(id), let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        let info = recordings[i]
        let moved: URL
        do {
            moved = try RecentlyDeleted.shared.add(info)
        } catch {
            status = Status(text: "Couldn't delete \(info.title): \(error.localizedDescription)")
            return
        }
        forgetRecording(id)

        // On the ⌘Z list for good, not only while the Undo link shows.
        let step = pushUndo("Moved \(info.title) to Recently deleted.", recording: nil, restores: id) { [weak self] in
            guard RecentlyDeleted.shared.items.contains(where: { $0.id == id }) else { return }
            if self?.deletedNote?.info.id == id {
                self?.deletedNote = nil
                if self?.status?.action == .undoDelete { self?.status = nil }
            }
            self?.putBack(id)
        }
        let note = DeletedNote(info: info, trashURL: moved, step: step)
        deletedNote = note
        if isBusy {
            status = Status(text: "Moved \(info.title) to Recently deleted.", action: .undoDelete)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.deletedNote == note else { return }
            self.deletedNote = nil
            if self.status?.action == .undoDelete { self.status = nil }
        }
    }

    private func forgetRecording(_ id: UUID) {
        recordings.removeAll { $0.id == id }
        Playback.shared.forget(id)
        Transcriber.shared.forget(id)
        LiveTranscriber.shared.forget(id)
        if selection == id { selection = nil }
        if stoppedNote?.recordingID == id { stoppedNote = nil }
    }

    func undoDelete() {
        guard let note = deletedNote else { return }
        deletedNote = nil
        if status?.action == .undoDelete { status = nil }
        undoStack.removeAll { $0.id == note.step }
        putBack(note.info.id)
    }

    /// Recently deleted > Put Back (and Undo).
    func putBack(_ id: UUID) {
        do {
            try RecentlyDeleted.shared.restore(id)
        } catch {
            status = Status(text: "Couldn't put it back: \(error.localizedDescription)")
            return
        }
        // Its delete step (and the 10 s Undo) is done now.
        undoStack.removeAll { $0.restores == id }
        if deletedNote?.info.id == id {
            deletedNote = nil
            if status?.action == .undoDelete { status = nil }
        }
        reload()
        Transcriber.shared.reload(id)
        LiveTranscriber.shared.reload(id)
        showingDeleted = false
        selection = id
    }

    /// Settings > Storage > Delete All Recordings. Everything but the one
    /// recording now goes to Recently deleted, with one Undo.
    func deleteAll() {
        var moved: [UUID] = []
        for info in recordings where canDelete(info.id) {
            if Transcriber.shared.importing.contains(info.id) {
                cancelImport(info.id)
                continue
            }
            if (try? RecentlyDeleted.shared.add(info)) != nil {
                forgetRecording(info.id)
                moved.append(info.id)
            }
        }
        guard !moved.isEmpty else { return }
        let text = moved.count == 1 ? "Moved 1 recording to Recently deleted." : "Moved \(moved.count) recordings to Recently deleted."
        offerLineUndo(text) { [weak self] in
            for id in moved { try? RecentlyDeleted.shared.restore(id) }
            self?.reload()
            for id in moved {
                Transcriber.shared.reload(id)
                LiveTranscriber.shared.reload(id)
            }
        }
    }

    /// Right-click > Keep Audio: the old-audio cleanup leaves it alone.
    func setKeepAudio(_ id: UUID, _ keep: Bool) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].keepAudio = keep ? true : nil
        guard persist(recordings[i]) else { return }
        flash(keep ? "\(recordings[i].title) keeps its audio." : "\(recordings[i].title)'s audio is deleted after \(AudioCleanup.days) days like the others.")
    }

    /// Old-audio cleanup: the audio files go for good, the text stays.
    func removeAudioForGood(_ id: UUID) -> Bool {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return false }
        Playback.shared.forget(id)
        for url in RecordingStore.audioFiles(id) {
            do { try FileManager.default.removeItem(at: url) } catch { return false }
        }
        recordings[i].audioDeletedAt = Date()
        persist(recordings[i])
        return true
    }

    // MARK: - Audio (play in the app, delete audio only)

    /// Selects the audio in Finder, or the folder if the audio was deleted.
    func showInFinder(_ info: RecordingInfo) {
        let audio = RecordingStore.playbackURL(info.id)
        let target = FileManager.default.fileExists(atPath: audio.path) ? audio : RecordingStore.folder(info.id)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// Opens the player bar under the transcript and plays.
    func playAudio(_ id: UUID, from start: Double? = nil) {
        guard id != currentID else { return }
        if let info = recordings.first(where: { $0.id == id }), !info.hasAudio {
            flash("The audio for \(info.title) was deleted. The text is still here.")
            return
        }
        if let problem = Playback.shared.play(id, from: start) {
            flash(problem)
            return
        }
        selection = id // the player bar lives under that transcript
    }

    /// Why Delete Audio Only can't be used right now, nil if it can.
    func audioDeleteBlocker(_ id: UUID) -> String? {
        guard let info = recordings.first(where: { $0.id == id }) else { return "Not found" }
        if !info.hasAudio { return "Audio already deleted" }
        if id == currentID { return "Still recording" }
        let t = Transcriber.shared
        if t.active?.id == id || t.isQueued(id) || t.importing.contains(id) || t.isGrowing(id) {
            return "Wait for the text to finish"
        }
        if AudioSquash.shared.working == id { return "Shrinking the audio" }
        return nil
    }

    /// Moves only the audio files to the Mac's Trash. The transcript stays.
    /// Undo for 10 s; after that it's still in the Trash.
    func deleteAudio(_ id: UUID) {
        guard audioDeleteBlocker(id) == nil, let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        let info = recordings[i]
        // The spec says never delete audio before its text is done. Ask, since it can't be finished after.
        let t = Transcriber.shared
        let noText = (LiveTranscriber.shared.texts[id]?.lines.isEmpty ?? true) && t.transcripts[id]?.finished != true
        if t.isUnfinished(id) || noText {
            let alert = NSAlert()
            alert.messageText = "Delete the audio before the text is finished?"
            alert.informativeText = "Without the audio, Verbatim can't finish or redo the text for \(info.title). The text that's there now stays."
            alert.addButton(withTitle: "Delete Audio")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Playback.shared.forget(id)
        // The 16 kHz audio and the 48 kHz listening copy go together.
        var moved: [(trash: URL, original: URL)] = []
        for audio in RecordingStore.audioFiles(id) {
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: audio, resultingItemURL: &trashed)
            } catch {
                // Put back what already went, so it's all or nothing.
                for m in moved { try? FileManager.default.moveItem(at: m.trash, to: m.original) }
                status = Status(text: "Couldn't delete the audio: \(error.localizedDescription)")
                return
            }
            if let url = trashed as URL? { moved.append((url, audio)) }
        }
        recordings[i].audioDeletedAt = Date()
        persist(recordings[i])

        guard !moved.isEmpty else { return }
        audioUndo = (id, moved)
        let s = Status(text: "Deleted the audio for \(info.title). The text stays.", action: .undoAudioDelete)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.status == s else { return }
            self.status = nil
            self.audioUndo = nil
        }
    }

    func undoAudioDelete() {
        guard let undo = audioUndo else { return }
        audioUndo = nil
        if status?.action == .undoAudioDelete { status = nil }
        do {
            for f in undo.files { try FileManager.default.moveItem(at: f.trash, to: f.original) }
        } catch {
            status = Status(text: "Couldn't bring the audio back. It's still in the Trash.")
            return
        }
        guard let i = recordings.firstIndex(where: { $0.id == undo.id }) else { return }
        recordings[i].audioDeletedAt = nil
        persist(recordings[i])
    }

    // MARK: - Import (Voice Memos and other files)

    /// The file picker behind the sidebar button and File > Transcribe a Recording (⌘O).
    func chooseFilesToImport() {
        let panel = NSOpenPanel()
        // Only kinds Verbatim can open (C3: it offered .flac, then refused it).
        panel.allowedContentTypes = AudioImport.allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.message = "Pick a Voice Memo or other recording. Your original file isn't changed."
        panel.prompt = "Transcribe"
        if panel.runModal() == .OK { importAudio(panel.urls) }
    }

    /// Copies each file in as a new recording, then transcribes it. It goes
    /// into the group on screen (B16: a memo dropped on the start page
    /// showing "English" used to land in Recents).
    func importAudio(_ urls: [URL]) {
        importAudio(urls, into: groupOnScreen)
    }

    /// The group the start page records into, or the open recording's group.
    private var groupOnScreen: UUID? {
        if showingDeleted { return nil }
        guard let id = selection else { return GroupStore.shared.group(GroupStore.shared.lastUsedID)?.id }
        return GroupStore.shared.group(info(id)?.groupID)?.id
    }

    /// Dropped on a group in the sidebar, or picked for one.
    func importAudio(_ urls: [URL], into group: UUID?) {
        let bad = urls.filter { !AudioImport.canImport($0) }
        if !bad.isEmpty {
            // Every file that was left out, not only the first (C3).
            let names = bad.map(\.lastPathComponent)
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
            show("Verbatim can't open \(list). Use \(AudioImport.allowedText).")
        }
        for url in urls where AudioImport.canImport(url) {
            importOne(url, into: group)
        }
    }

    private func importOne(_ url: URL, into group: UUID?) {
        // Dropped twice while the first copy is still going: show that one.
        if let same = recordings.first(where: { $0.importingPath == url.path && Transcriber.shared.importing.contains($0.id) }) {
            selection = same.id
            return
        }
        let attrs = try? url.resourceValues(forKeys: [.creationDateKey])
        var info = RecordingInfo(
            id: UUID(),
            title: url.deletingPathExtension().lastPathComponent,
            createdAt: attrs?.creationDate ?? Date(),
            state: .stopped
        )
        info.importedFrom = url.lastPathComponent
        info.importingPath = url.path
        info.groupID = group
        info.autoTitle = true
        do {
            try RecordingStore.create(info)
        } catch {
            show("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        recordings.append(info)
        recordings.sort { $0.createdAt > $1.createdAt }
        if let group { GroupStore.shared.update(group) { $0.collapsed = false } }
        if isBusy {
            // Recording: stay on the live page (B16), say where it went.
            let place = GroupStore.shared.group(group)?.name ?? "Recents"
            show("Importing \(url.lastPathComponent) into \(place). The text comes after you stop recording.")
        } else {
            selection = info.id
        }
        runImport(info.id, from: url, access: url.startAccessingSecurityScopedResource())
    }

    /// Copies the sound in, with progress and Cancel (UX round 2, A6). Also
    /// used at launch for a copy that was cut off by quitting.
    fileprivate func runImport(_ id: UUID, from url: URL, access: Bool) {
        Transcriber.shared.setImporting(id, true)
        let destination = RecordingStore.wavURL(id)
        importTasks[id] = Task { [weak self] in
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let samples = try await AudioImport.convert(url, to: destination) { fraction in
                    Task { @MainActor in Transcriber.shared.setImportProgress(id, fraction) }
                }
                try Task.checkCancellation()
                guard let self, let i = self.recordings.firstIndex(where: { $0.id == id }) else { return }
                self.importTasks[id] = nil
                self.recordings[i].samples = samples
                self.recordings[i].endedAt = self.recordings[i].createdAt.addingTimeInterval(Double(samples) / 16_000)
                self.recordings[i].importingPath = nil
                self.persist(self.recordings[i])
                Transcriber.shared.setImporting(id, false)
                Transcriber.shared.enqueue(id)
            } catch {
                guard let self else { return }
                self.importTasks[id] = nil
                Transcriber.shared.setImporting(id, false)
                try? FileManager.default.removeItem(at: RecordingStore.folder(id))
                self.recordings.removeAll { $0.id == id }
                if self.selection == id { self.selection = nil }
                if error is CancellationError || Task.isCancelled {
                    self.show("Stopped importing \(url.lastPathComponent). Your original file isn't touched.")
                } else {
                    self.show("Couldn't import \(url.lastPathComponent): \(AudioImport.plainWords(error))")
                }
            }
        }
    }

    /// Cancel while a file is being copied in, or Delete on it: nothing of it
    /// is kept (it's only a copy, the original stays where it was).
    func cancelImport(_ id: UUID) {
        importTasks[id]?.cancel()
    }

    /// Imports cut off by quitting: the copy starts over if the original file
    /// is still there. If not, the half copy goes and a note says so.
    private func recoverImports(_ all: inout [RecordingInfo]) -> [(UUID, URL)] {
        var again: [(UUID, URL)] = []
        var lost: [String] = []
        for info in all {
            guard let path = info.importingPath else { continue }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isReadableFile(atPath: path) {
                Transcriber.shared.setImporting(info.id, true) // before Transcriber.start looks
                again.append((info.id, url))
            } else {
                try? FileManager.default.removeItem(at: RecordingStore.folder(info.id))
                lost.append(info.importedFrom ?? url.lastPathComponent)
            }
        }
        all.removeAll { info in info.importingPath != nil && !again.contains { $0.0 == info.id } }
        if let name = lost.last {
            recoveryNotice = "Verbatim quit while importing \(name) and couldn't open the file again. Drop it in again to transcribe it."
        }
        return again
    }

    /// A message in the status spot. When not recording, it clears itself.
    /// While recording it stays, so it isn't missed, unless a warning is
    /// waiting under it: then it makes way after 30 s (B1 review).
    func show(_ text: String) {
        let s = Status(text: text)
        status = s
        let busy = isBusy
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(busy ? 30 : 12))
            guard let self, self.status == s else { return }
            if !self.isBusy || self.warning != nil { self.status = nil }
        }
    }

    func clearStatus() { status = nil }

    /// A note that stays until something replaces it.
    func hold(_ text: String) { status = Status(text: text) }

    /// A short note that goes away by itself, even while recording.
    func flash(_ text: String) {
        let s = Status(text: text)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.status == s { self?.status = nil }
        }
    }

    /// "Line edited. Undo" in the status spot for 10 seconds, and on the
    /// ⌘Z list for good (until the app quits, last 50 changes).
    /// `recording`: the recording the change is in (nil: not one recording,
    /// like a group delete or a move).
    func offerLineUndo(_ text: String, in recording: UUID? = nil, undo: @escaping () -> Void) {
        pushUndo(text, recording: recording, run: undo)
        // The Undo link only for a change you can see: a box saved while
        // switching recordings goes on ⌘Z, but its link would undo a
        // recording that's not on screen.
        if let recording, recording != selection, recording != currentID { return }
        let s = Status(text: text, action: .undoLine)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.status == s else { return }
            self.status = nil
        }
    }

    @discardableResult
    private func pushUndo(_ text: String, recording: UUID?, restores: UUID? = nil,
                          run: @escaping () -> Void) -> UUID {
        let step = UndoStep(text: text, recording: recording, restores: restores, run: run)
        undoStack.append(step)
        if undoStack.count > 50 { undoStack.removeFirst() }
        undoSerial += 1
        return step.id
    }

    /// A change made in Settings (a word, a fix, a name removed): on the ⌘Z
    /// list too, not only its own Undo link there (B13: only the last one
    /// could be undone). Returns what the link runs. It undoes only once,
    /// whichever is used.
    func settingsUndo(_ text: String, run: @escaping () -> Void) -> () -> Void {
        var done = false
        let once = {
            guard !done else { return }
            done = true
            run()
        }
        let id = pushUndo(text, recording: nil, run: once)
        return { [weak self] in
            once()
            self?.undoStack.removeAll { $0.id == id }
        }
    }

    /// The Undo link in the bottom bar went with the recording on screen:
    /// it goes when another recording opens, so it never changes one you
    /// can't see (UX round 2, A4).
    func selectionChanged() {
        if status?.action == .undoLine { status = nil }
    }

    /// Edit > Undo (⌘Z). Typing in a box: undoes the typing, like any Mac
    /// app. Otherwise: Undo Stop right after Stop, audio that still shows
    /// Undo, then the newest change in the recording on screen.
    func undo() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            return
        }
        // Just stopped and nothing newer: ⌘Z is Undo Stop, not an old edit.
        if let note = stoppedNote, phase == .idle, note.serial == undoSerial {
            undoStop()
            return
        }
        switch status?.action {
        case .undoAudioDelete?: perform(.undoAudioDelete)
        default:
            if status?.action == .undoLine { status = nil }
            undoLastChange()
        }
    }

    /// Edit > Redo (⇧⌘Z): only for typing in a box.
    func redo() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            return
        }
        // Item 11: it did nothing, with no word why.
        flash("Redo only works while typing in a box. Something undone can be done again by hand.")
    }

    /// The newest step ⌘Z may take: not one recording, the recording on
    /// screen, or the one being recorded (the mini window edits that one).
    /// Steps of a recording in Recently deleted wait (Put Back brings them back).
    private func undoable(_ step: UndoStep) -> Bool {
        // Put back or deleted for good already: nothing left to undo.
        if let r = step.restores { return RecentlyDeleted.shared.items.contains { $0.id == r } }
        guard let id = step.recording else { return true }
        guard recordings.contains(where: { $0.id == id }) else { return false }
        return id == selection || id == currentID
    }

    private func undoLastChange() {
        guard let i = undoStack.lastIndex(where: { undoable($0) }) else {
            flash(undoStack.isEmpty ? "Nothing to undo." : "Nothing to undo in this recording.")
            return
        }
        let step = undoStack.remove(at: i)
        if let id = deletedNote?.step, id == step.id { deletedNote = nil }
        step.run()
        var text = "Undid: \(Self.undoName(step.text))"
        if let id = step.recording, id != selection, let title = info(id)?.title {
            text += " (in \(title))"
        }
        flash(text)
    }

    /// "Line edited." becomes "line edited." for "Undid: line edited."
    /// Names at the start (Mr. Yurt, English) stay as they are.
    private static func undoName(_ text: String) -> String {
        let common = ["Line", "Deleted", "Moved", "Marker", "Note", "Remembered."]
        guard let word = text.split(separator: " ").first, common.contains(String(word)) else { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    /// A message with a text link that does `run`, for 10 seconds.
    func offer(_ text: String, _ action: Status.Action, run: @escaping () -> Void) {
        offered = run
        let s = Status(text: text, action: action)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.status == s else { return }
            self.status = nil
            self.offered = nil
        }
    }

    /// "Saved 2026-11-10 English.md. Show in Finder" for 10 seconds.
    func showFile(_ url: URL, text: String) {
        fileToShow = url
        let s = Status(text: text, action: .showFile)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if self?.status == s { self?.status = nil }
        }
    }

    // MARK: - Library

    /// Where the last copy ended, for "Copy new since last copy".
    func setCopiedUpTo(_ id: UUID, _ seconds: Double) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].copiedUpTo = seconds
        persist(recordings[i])
    }

    /// Markers (step 7b), seconds into the audio. See Markers.swift.
    func setMarkers(_ id: UUID, _ markers: [Double]) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].markers = markers.isEmpty ? nil : markers.sorted()
        persist(recordings[i])
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = recordings.firstIndex(where: { $0.id == id }),
              recordings[i].title != trimmed else { return }
        let oldTitle = recordings[i].title
        let oldAuto = recordings[i].autoTitle
        recordings[i].title = trimmed
        recordings[i].autoTitle = nil // Ryan named it: auto-naming leaves it alone
        persist(recordings[i])
        // Item 4: renaming had no Undo.
        offerLineUndo("Renamed to \(trimmed).", in: id) { [weak self] in
            guard let self, let i = self.recordings.firstIndex(where: { $0.id == id }) else { return }
            self.recordings[i].title = oldTitle
            self.recordings[i].autoTitle = oldAuto
            self.persist(self.recordings[i])
        }
    }

    /// On the ⌘Z list without taking over the bottom bar (its message is
    /// already showing something else, like "Changed to Mr. Yurt").
    func addUndo(_ text: String, in recording: UUID?, run: @escaping () -> Void) {
        pushUndo(text, recording: recording, run: run)
    }

    /// Auto-naming (step 10): only if Ryan hasn't renamed it meanwhile.
    func setAutoTitle(_ id: UUID, _ title: String) {
        guard let i = recordingIndex(id), recordings[i].autoTitle == true else { return }
        recordings[i].title = title
        recordings[i].autoTitle = false // named once; don't redo it
        persist(recordings[i])
    }

    func recordingIndex(_ id: UUID) -> Int? { recordings.firstIndex { $0.id == id } }

    /// Changes one recording and saves it. The one being recorded is saved too.
    func changeRecording(_ i: Int, _ change: (inout RecordingInfo) -> Void) {
        guard recordings.indices.contains(i) else { return }
        change(&recordings[i])
        persist(recordings[i])
    }

    /// "Wed 12 Nov": a new recording's name until auto-naming or Ryan changes it.
    nonisolated static func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Saves one recording's recording.json. If it fails (disk full, folder
    /// locked), says so once and keeps the change in memory: `reload` keeps
    /// it instead of putting the old file back, and tries again. It used to
    /// fail silently and the change was undone the next time the app was
    /// clicked (renames, notes, markers, Keep Audio).
    @discardableResult
    func persist(_ info: RecordingInfo) -> Bool {
        do {
            try RecordingStore.save(info)
            unsaved.remove(info.id)
            return true
        } catch {
            if unsaved.insert(info.id).inserted {
                status = Status(text: "Couldn't save the change to \(info.title): \(error.localizedDescription) Verbatim keeps it and tries again.")
            }
            return false
        }
    }

    /// Tries the saves that failed again. Returns the ones that still fail.
    private func retryUnsaved() -> [UUID: RecordingInfo] {
        var still: [UUID: RecordingInfo] = [:]
        for id in unsaved {
            guard let info = recordings.first(where: { $0.id == id }),
                  FileManager.default.fileExists(atPath: RecordingStore.folder(id).path) else {
                unsaved.remove(id) // gone: nothing left to save
                continue
            }
            if persist(info) {
                flash("Saved the change to \(info.title).")
            } else {
                still[id] = info
            }
        }
        return still
    }

    func reload() {
        let active = current
        let mine = retryUnsaved()
        var list = RecordingStore.loadAll()
        if let active, let i = list.firstIndex(where: { $0.id == active.id }) {
            list[i] = active // the live copy is newer than the file
        }
        for (i, info) in list.enumerated() where mine[info.id] != nil {
            list[i] = mine[info.id]! // the file is older than what Ryan did
        }
        recordings = list
        if let s = selection, !list.contains(where: { $0.id == s }) { selection = nil }
    }

    /// Settings changed the mic. Switch now if recording, so it takes effect right away.
    func micSettingChanged() {
        refreshMicName()
        guard phase == .recording else { return }
        let (dev, _) = Microphones.resolve()
        guard let dev, dev.uniqueID != device?.uniqueID else { return }
        switchMic(to: dev, message: "Switched to the \(Microphones.mic(for: dev).displayName).")
    }

    func refreshPermission() {
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        // Turned back on: the "access is off" message is old news.
        if micPermission == .authorized, status?.action == .openMicSettings { status = nil }
    }

    func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Audio callbacks

    private func wirePipeline() {
        pipeline.onLevel = { [weak self] level, samples in
            Task { @MainActor in self?.receive(level: level, samples: samples) }
        }
        pipeline.onWriteError = { [weak self] _ in
            Task { @MainActor in self?.writeFailed() }
        }
        let live = LiveTranscriber.shared.feed
        pipeline.onSamples = { live.yield(.samples($0)) }
        pipeline.onRuntimeError = { [weak self] in
            MainActor.assumeIsolated { self?.captureFailed() }
        }
    }

    private func receive(level: Float, samples: Int64) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
        elapsed = Double(samples) / 16_000
        restartedAfterError = false
        let clock = MenuBarIcon.shortClock(elapsed)
        if clock != menuClock { menuClock = clock }

        let quietMinutes = Self.quietMinutes
        if level > 0.3 {
            lastLoud = Date()
            if quietWarned {
                quietWarned = false
                clearStanding { $0.action == .stopRecording }
                Messages.shared.withdraw("stillRecording")
            }
        } else if !quietWarned, quietMinutes > 0, Date().timeIntervalSince(lastLoud) > Double(quietMinutes) * 60 {
            quietWarned = true
            status = Status(text: "Quiet for \(quietMinutes) minutes. Still in class?", action: .stopRecording, standing: true)
            Messages.shared.post(Messages.stillRecording(minutes: quietMinutes, elapsed: elapsed))
        }
        if Date().timeIntervalSince(lastBatteryCheck) > 60 {
            lastBatteryCheck = Date()
            checkBattery()
        }

        if Date().timeIntervalSince(lastSave) > 10 {
            updateCurrent { $0.samples = samples }
            saveCurrent()
        }
        // C10: say so 10 minutes before the 3 hour stop, not only after.
        if !limitWarned, elapsed >= Self.maxLength - 600, elapsed < Self.maxLength {
            limitWarned = true
            status = Status(text: "10 minutes left: a recording stops at 3 hours. Start a new one after.", standing: true)
        }
        if elapsed >= Self.maxLength {
            let title = current?.title ?? "The recording"
            let note = "Stopped at 3 hours, the longest a recording can be. Saved."
            stop(note: note)
            // No Undo Stop: it would only stop again at once (C10).
            finishStopped()
            show(note)
            Messages.shared.post(Messages.stoppedAtLimit(title))
        }
    }

    /// Step 10: warn once at 15% on battery; the warning goes when plugged in.
    private func checkBattery() {
        guard let battery = Battery.read() else { return }
        if battery.onBattery, battery.percent <= 15 {
            guard !batteryWarned else { return }
            batteryWarned = true
            if status == nil || status?.action == nil {
                status = Status(text: "Battery at \(battery.percent)%. Plug in to keep recording.", standing: true)
            }
            Messages.shared.post(Messages.battery(battery.percent))
        } else if batteryWarned, !battery.onBattery {
            batteryWarned = false
            clearStanding { $0.text.hasPrefix("Battery at") }
            Messages.shared.withdraw("battery")
        }
    }

    private func writeFailed() {
        guard phase == .recording else { return }
        pipeline.stopCapture()
        LiveTranscriber.shared.micStopped()
        addEvent(.paused, note: "write failed")
        updateCurrent { $0.state = .paused }
        phase = .paused
        saveCurrent()
        status = Status(text: "Can't save audio, the disk is full. Free up space, then", action: .resume, standing: true)
        Messages.shared.post(Messages.problem("Recording paused: the disk is full. Free up space, then press Resume."))
        // Like any pause: the Mac may sleep, and it asks later (A9).
        endKeepAwake()
        askIfStillPaused()
    }

    private func captureFailed() {
        guard phase == .recording, let dev = device ?? Microphones.builtIn() else { return }
        if restartedAfterError {
            pause()
            status = Status(text: "The mic stopped working. Check it, then", action: .resume, standing: true)
            Messages.shared.post(Messages.problem("Recording paused: the mic stopped working. Check it, then press Resume."))
            return
        }
        restartedAfterError = true
        switchMic(to: dev, message: "The mic stopped for a moment. Recording again.")
    }

    private func switchMic(to dev: AVCaptureDevice, message: String) {
        do {
            try pipeline.startCapture(device: dev)
            device = dev
            refreshMicName()
            addEvent(.micChanged, note: Microphones.mic(for: dev).displayName)
            saveCurrent()
            // Old mic warnings are no longer true.
            clearStanding { $0.text.hasPrefix("Your chosen mic") || $0.text.hasPrefix("Mic unplugged") }
            status = Status(text: message)
        } catch {
            pause()
            status = Status(text: "Couldn't use the mic. Plug it back in, then", action: .resume, standing: true)
        }
    }

    // MARK: - Sleep, unplugged mics, app active

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.object as? AVCaptureDevice)?.uniqueID
            MainActor.assumeIsolated { self?.deviceDisconnected(id) }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermission()
                self?.reload()
            }
        })
    }

    private func willSleep() {
        guard phase == .recording else { return }
        pipeline.stopCapture()
        pipeline.flush()
        LiveTranscriber.shared.micStopped()
        asleepSince = Date()
        addEvent(.asleep)
        saveCurrent()
    }

    private func didWake() {
        guard let since = asleepSince else { return }
        asleepSince = nil
        guard phase == .recording else { return }
        let dev = Microphones.resolve().device ?? device
        guard let dev else { pause(); return }
        do {
            try pipeline.startCapture(device: dev)
            device = dev
        } catch {
            pause()
            status = Status(text: "Couldn't restart the mic after sleep.", action: .resume, standing: true)
            return
        }
        addEvent(.woke)
        saveCurrent()
        // The quiet minutes start again: asleep is not quiet (B2: "Still
        // recording?" used to replace this message at once). An old "Still
        // in class?" from before the sleep goes too, or it would come back.
        lastLoud = Date()
        quietWarned = false
        clearStanding { $0.action == .stopRecording }
        Messages.shared.withdraw("stillRecording")
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        // The tip only the first time.
        let tipKey = "toldKeepLidOpen"
        let tip = UserDefaults.standard.bool(forKey: tipKey) ? "" : " Keep the lid open in class."
        UserDefaults.standard.set(true, forKey: tipKey)
        status = Status(text: "Mac was asleep \(since.formatted(t)) to \(Date().formatted(t)).\(tip)")
    }

    private func deviceDisconnected(_ id: String?) {
        guard isBusy, let id, id == device?.uniqueID else { return }
        guard let fallback = Microphones.builtIn(), fallback.uniqueID != id else {
            pause()
            status = Status(text: "Mic unplugged and no other mic found. Plug one in, then", action: .resume, standing: true)
            Messages.shared.post(Messages.problem("Recording paused: the mic was unplugged. Plug one in, then press Resume."))
            return
        }
        if phase == .recording {
            switchMic(to: fallback, message: "Mic unplugged. Using the MacBook mic.")
        } else {
            device = fallback
            status = Status(text: "Mic unplugged. Resume will use the MacBook mic.", standing: true)
        }
    }

    // MARK: - Crash recovery

    /// Anything still marked as recording when the app starts was cut off by a
    /// crash or power loss. Fix the audio file and mark it stopped.
    private func recoverUnfinished(_ all: inout [RecordingInfo]) {
        var notices: [String] = []
        for (i, var info) in all.enumerated() where info.isActive {
            let audio = RecordingStore.wavURL(info.id)
            let samples = (try? WavWriter.repair(audio)) ?? info.samples
            let listen = RecordingStore.listenWavURL(info.id)
            if FileManager.default.fileExists(atPath: listen.path) {
                _ = try? WavWriter.repair(listen, rate: WavWriter.listenRate)
            }
            let modified = (try? audio.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let endedAt = modified ?? info.createdAt.addingTimeInterval(info.duration)
            info.samples = samples
            info.state = .stopped
            info.endedAt = endedAt
            info.events.append(.init(kind: .recovered, at: Date(), sample: samples))
            try? RecordingStore.save(info)
            all[i] = info
            let time = endedAt.formatted(date: .omitted, time: .shortened)
            notices.append("Verbatim quit during \(info.title) at \(time). The audio up to then was saved.")
        }
        recoveryNotice = notices.last
    }

    // MARK: - Helpers

    private func updateCurrent(_ change: (inout RecordingInfo) -> Void) {
        guard let id = currentID, let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
    }

    private func addEvent(_ kind: RecordingInfo.Event.Kind, note: String? = nil) {
        let sample = pipeline.samplesWritten
        updateCurrent {
            if sample > 0 { $0.samples = max($0.samples, sample) }
            $0.events.append(.init(kind: kind, at: Date(), sample: $0.samples, note: note))
        }
    }

    private func saveCurrent() {
        guard let info = current else { return }
        persist(info)
        lastSave = Date()
    }

    private func refreshMicName() {
        if let device {
            micName = Microphones.mic(for: device).displayName
        } else if let d = Microphones.resolve().device {
            micName = Microphones.mic(for: d).displayName
        }
    }

    private func beginKeepAwake() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Recording a class"
        )
    }

    private func endKeepAwake() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    static func minutesText(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return "under 1 min" }
        return "\(m) min"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
