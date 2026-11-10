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
        enum Action { case stopRecording, resume, undoDelete, undoLine, showFile, undoAudioDelete, changeVoice }
        var text: String
        var action: Action?
        var id = UUID()
    }

    /// Shown for 10 s after Stop, with Undo Stop.
    struct StoppedNote: Equatable {
        var recordingID: UUID
        var text: String
    }

    static let barCount = 40
    static let maxLength: TimeInterval = 3 * 3600
    static let quietLimit: TimeInterval = 10 * 60
    static let bytesPerHour: Int64 = 16_000 * 2 * 3600

    private(set) var phase: Phase = .idle
    private(set) var recordings: [RecordingInfo] = []
    private(set) var currentID: UUID?
    var selection: UUID?
    private(set) var levels: [Float] = Array(repeating: 0, count: RecorderModel.barCount)
    private(set) var elapsed: TimeInterval = 0
    private(set) var status: Status?
    private(set) var stoppedNote: StoppedNote?
    /// Shown for 10 s after Move to Trash, with Undo.
    struct DeletedNote: Equatable {
        var info: RecordingInfo
        var trashURL: URL
        var id = UUID()
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
    private(set) var micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var micName = "MacBook mic"

    @ObservationIgnored private let pipeline = AudioPipeline()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastLoud = Date()
    @ObservationIgnored private var quietWarned = false
    @ObservationIgnored private var asleepSince: Date?
    @ObservationIgnored private var restartedAfterError = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lineUndo: (() -> Void)?
    @ObservationIgnored private var fileToShow: URL?
    /// What the text link in the status spot does, for `offer`.
    @ObservationIgnored private var offered: (() -> Void)?
    /// Delete Audio Only, for Undo: which recording and where its audio went in the Trash.
    @ObservationIgnored private var audioUndo: (id: UUID, trashURL: URL, original: URL)?

    var current: RecordingInfo? { recordings.first { $0.id == currentID } }
    var isBusy: Bool { phase != .idle }

    private init() {
        recoverUnfinished()
        recordings = RecordingStore.loadAll()
        refreshMicName()
        wirePipeline()
        observeSystem()
        LiveTranscriber.shared.start(with: recordings) // loads the texts Transcriber looks at
        Transcriber.shared.start(with: recordings)
        // After init: AudioSquash looks at RecorderModel.shared.
        Task { @MainActor in AudioSquash.shared.run() }
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
    func showNewRecording() {
        selection = isBusy ? currentID : nil
    }

    func start() async {
        guard phase == .idle else { return }

        if micPermission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        guard micPermission == .authorized, phase == .idle else {
            selection = nil
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
        var info = RecordingInfo(id: UUID(), title: "English", createdAt: now, state: .recording)
        info.events.append(.init(kind: .started, at: now, sample: 0, note: Microphones.mic(for: dev).displayName))
        do {
            try RecordingStore.create(info)
            let writer = try WavWriter(creating: RecordingStore.wavURL(info.id))
            pipeline.attach(writer)
            LiveTranscriber.shared.recordingStarted(info.id, samples: 0)
            try pipeline.startCapture(device: dev)
            Transcriber.shared.recordingStarted(info.id)
        } catch {
            pipeline.detach()
            LiveTranscriber.shared.recordingStopped()
            status = Status(text: "Couldn't start recording: \(error.localizedDescription)")
            return
        }

        stoppedNote = nil
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
        phase = .recording
        beginKeepAwake()

        if fellBack {
            status = Status(text: "Your chosen mic isn't plugged in. Using the MacBook mic.")
        } else if let free = RecordingStore.freeSpace(), free < Self.bytesPerHour * 3 {
            let hours = Double(free) / Double(Self.bytesPerHour)
            status = Status(text: String(format: "Disk is almost full: room for about %.1f hours of audio.", hours))
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
        if status?.action == .stopRecording { status = nil }
    }

    func resume() {
        guard phase == .paused else { return }
        let (dev, fellBack) = Microphones.resolve()
        guard let dev else {
            status = Status(text: "No microphone found. Plug one in, then press Resume.")
            return
        }
        do {
            try pipeline.startCapture(device: dev)
        } catch {
            status = Status(text: "Couldn't use the mic: \(error.localizedDescription)", action: .resume)
            return
        }
        device = dev
        refreshMicName()
        addEvent(.resumed)
        updateCurrent { $0.state = .recording }
        phase = .recording
        lastLoud = Date()
        quietWarned = false
        status = fellBack ? Status(text: "Your chosen mic isn't plugged in. Using the MacBook mic.") : nil
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

        let info = current
        phase = .idle
        currentID = nil
        device = nil
        status = nil
        levels = Array(repeating: 0, count: Self.barCount)

        let title = info?.title ?? "Recording"
        let length = Self.minutesText(info?.duration ?? 0)
        let text = note ?? "Saved \(title), \(length)."
        let stopped = StoppedNote(recordingID: id, text: text)
        stoppedNote = stopped
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.stoppedNote == stopped else { return }
            self.stoppedNote = nil
            // Undo Stop is no longer possible, so the recording is final. Files
            // waiting for the recording to end can start now.
            Transcriber.shared.recordingFinal(id)
        }
    }

    /// Continues the recording that was just stopped, in the same audio file.
    func undoStop() {
        guard phase == .idle, let note = stoppedNote,
              let info = recordings.first(where: { $0.id == note.recordingID }) else { return }
        stoppedNote = nil
        let (dev, fellBack) = Microphones.resolve()
        guard let dev else {
            status = Status(text: "No microphone found, so the recording stayed stopped.")
            return
        }
        do {
            let writer = try WavWriter(appendingTo: RecordingStore.wavURL(info.id))
            pipeline.attach(writer)
            LiveTranscriber.shared.recordingStarted(info.id, samples: writer.samplesWritten)
            try pipeline.startCapture(device: dev)
            Transcriber.shared.recordingStarted(info.id)
        } catch {
            pipeline.detach()
            LiveTranscriber.shared.recordingStopped()
            status = Status(text: "Couldn't continue the recording: \(error.localizedDescription)")
            return
        }
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
        status = fellBack ? Status(text: "Your chosen mic isn't plugged in. Using the MacBook mic.") : nil
        saveCurrent()
    }

    func perform(_ action: Status.Action) {
        switch action {
        case .stopRecording: stop()
        case .resume: resume()
        case .undoDelete: undoDelete()
        case .undoLine:
            lineUndo?()
            lineUndo = nil
            if status?.action == .undoLine { status = nil }
        case .showFile:
            if let url = fileToShow { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            status = nil
        case .undoAudioDelete: undoAudioDelete()
        case .changeVoice:
            let run = offered
            offered = nil
            if status?.action == .changeVoice { status = nil }
            run?()
        }
    }

    // MARK: - Delete (Move to Trash, with Undo)

    func canDelete(_ id: UUID) -> Bool { id != currentID }

    /// Moves the recording's folder to the Mac's Trash. Undo for 10 s, and it
    /// stays in the Trash after that. In-app "Recently deleted" comes in step 9.
    func delete(_ id: UUID) {
        guard canDelete(id), let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        let info = recordings[i]
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: RecordingStore.folder(id), resultingItemURL: &trashed)
        } catch {
            status = Status(text: "Couldn't move \(info.title) to the Trash: \(error.localizedDescription)")
            return
        }
        recordings.remove(at: i)
        Playback.shared.forget(id)
        Transcriber.shared.forget(id)
        LiveTranscriber.shared.forget(id)
        if selection == id { selection = nil }
        if stoppedNote?.recordingID == id { stoppedNote = nil }
        guard let url = trashed as URL? else { return }

        let note = DeletedNote(info: info, trashURL: url)
        deletedNote = note
        if isBusy {
            status = Status(text: "Moved \(info.title) to the Trash.", action: .undoDelete)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.deletedNote == note else { return }
            self.deletedNote = nil
            if self.status?.action == .undoDelete { self.status = nil }
        }
    }

    func undoDelete() {
        guard let note = deletedNote else { return }
        deletedNote = nil
        if status?.action == .undoDelete { status = nil }
        do {
            try FileManager.default.moveItem(at: note.trashURL, to: RecordingStore.folder(note.info.id))
        } catch {
            status = Status(text: "Couldn't bring it back. It's still in the Trash.")
            return
        }
        reload()
        Transcriber.shared.reload(note.info.id)
        LiveTranscriber.shared.reload(note.info.id)
        selection = note.info.id
    }

    // MARK: - Audio (play in the app, delete audio only)

    /// Selects the audio in Finder, or the folder if the audio was deleted.
    func showInFinder(_ info: RecordingInfo) {
        let audio = RecordingStore.audioURL(info.id)
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

    /// Moves only audio.wav to the Mac's Trash. The transcript stays.
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
        let audio = RecordingStore.audioURL(id)
        var trashed: NSURL?
        if FileManager.default.fileExists(atPath: audio.path) {
            do {
                try FileManager.default.trashItem(at: audio, resultingItemURL: &trashed)
            } catch {
                status = Status(text: "Couldn't delete the audio: \(error.localizedDescription)")
                return
            }
        }
        recordings[i].audioDeletedAt = Date()
        try? RecordingStore.save(recordings[i])

        guard let url = trashed as URL? else { return }
        audioUndo = (id, url, audio)
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
            try FileManager.default.moveItem(at: undo.trashURL, to: undo.original)
        } catch {
            status = Status(text: "Couldn't bring the audio back. It's still in the Trash.")
            return
        }
        guard let i = recordings.firstIndex(where: { $0.id == undo.id }) else { return }
        recordings[i].audioDeletedAt = nil
        try? RecordingStore.save(recordings[i])
    }

    // MARK: - Import (Voice Memos and other files)

    /// The file picker behind the sidebar button and File > Transcribe a Recording (⌘O).
    func chooseFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        panel.message = "Pick a Voice Memo or other recording. Your original file isn't changed."
        panel.prompt = "Transcribe"
        if panel.runModal() == .OK { importAudio(panel.urls) }
    }

    /// Copies each file in as a new recording, then transcribes it.
    func importAudio(_ urls: [URL]) {
        let bad = urls.filter { !AudioImport.canImport($0) }
        if let first = bad.first {
            show("Verbatim can't open .\(first.pathExtension) files. Use \(AudioImport.allowedText).")
        }
        for url in urls where AudioImport.canImport(url) {
            importOne(url)
        }
    }

    private func importOne(_ url: URL) {
        let attrs = try? url.resourceValues(forKeys: [.creationDateKey])
        var info = RecordingInfo(
            id: UUID(),
            title: url.deletingPathExtension().lastPathComponent,
            createdAt: attrs?.creationDate ?? Date(),
            state: .stopped
        )
        info.importedFrom = url.lastPathComponent
        do {
            try RecordingStore.create(info)
        } catch {
            show("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        recordings.append(info)
        recordings.sort { $0.createdAt > $1.createdAt }
        selection = info.id
        Transcriber.shared.setImporting(info.id, true)

        let id = info.id
        let destination = RecordingStore.wavURL(id)
        let access = url.startAccessingSecurityScopedResource()
        Task { [weak self] in
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let samples = try await AudioImport.convert(url, to: destination)
                guard let self, let i = self.recordings.firstIndex(where: { $0.id == id }) else { return }
                self.recordings[i].samples = samples
                self.recordings[i].endedAt = self.recordings[i].createdAt.addingTimeInterval(Double(samples) / 16_000)
                try? RecordingStore.save(self.recordings[i])
                Transcriber.shared.setImporting(id, false)
                Transcriber.shared.enqueue(id)
            } catch {
                Transcriber.shared.setImporting(id, false)
                try? FileManager.default.removeItem(at: RecordingStore.folder(id))
                guard let self else { return }
                self.recordings.removeAll { $0.id == id }
                if self.selection == id { self.selection = nil }
                self.show("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// A message in the status spot. When not recording, it clears itself.
    func show(_ text: String) {
        let s = Status(text: text)
        status = s
        guard !isBusy else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            if self?.status == s, self?.isBusy == false { self?.status = nil }
        }
    }

    func clearStatus() { status = nil }

    /// A short note that goes away by itself, even while recording.
    func flash(_ text: String) {
        let s = Status(text: text)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.status == s { self?.status = nil }
        }
    }

    /// "Line edited. Undo" in the status spot for 10 seconds.
    func offerLineUndo(_ text: String, undo: @escaping () -> Void) {
        lineUndo = undo
        let s = Status(text: text, action: .undoLine)
        status = s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.status == s else { return }
            self.status = nil
            self.lineUndo = nil
        }
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
        try? RecordingStore.save(recordings[i])
    }

    /// Markers (step 7b), seconds into the audio. See Markers.swift.
    func setMarkers(_ id: UUID, _ markers: [Double]) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].markers = markers.isEmpty ? nil : markers.sorted()
        try? RecordingStore.save(recordings[i])
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].title = trimmed
        try? RecordingStore.save(recordings[i])
    }

    func reload() {
        let active = current
        var list = RecordingStore.loadAll()
        if let active, let i = list.firstIndex(where: { $0.id == active.id }) {
            list[i] = active // the live copy is newer than the file
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

        if level > 0.3 {
            lastLoud = Date()
            if quietWarned {
                quietWarned = false
                if status?.action == .stopRecording { status = nil }
            }
        } else if !quietWarned, Date().timeIntervalSince(lastLoud) > Self.quietLimit {
            quietWarned = true
            status = Status(text: "Quiet for 10 minutes. Still in class?", action: .stopRecording)
        }

        if Date().timeIntervalSince(lastSave) > 10 {
            updateCurrent { $0.samples = samples }
            saveCurrent()
        }
        if elapsed >= Self.maxLength {
            stop(note: "Stopped at 3 hours, the longest a recording can be. Saved.")
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
        status = Status(text: "Can't save audio, the disk is full. Free up space, then", action: .resume)
    }

    private func captureFailed() {
        guard phase == .recording, let dev = device ?? Microphones.builtIn() else { return }
        if restartedAfterError {
            pause()
            status = Status(text: "The mic stopped working. Check it, then", action: .resume)
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
            status = Status(text: message)
        } catch {
            pause()
            status = Status(text: "Couldn't use the mic. Plug it back in, then", action: .resume)
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
            status = Status(text: "Couldn't restart the mic after sleep.", action: .resume)
            return
        }
        addEvent(.woke)
        saveCurrent()
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        status = Status(text: "Mac was asleep \(since.formatted(t)) to \(Date().formatted(t)). Keep the lid open in class.")
    }

    private func deviceDisconnected(_ id: String?) {
        guard isBusy, let id, id == device?.uniqueID else { return }
        guard let fallback = Microphones.builtIn(), fallback.uniqueID != id else {
            pause()
            status = Status(text: "Mic unplugged and no other mic found. Plug one in, then", action: .resume)
            return
        }
        if phase == .recording {
            switchMic(to: fallback, message: "Mic unplugged. Using the MacBook mic.")
        } else {
            device = fallback
            status = Status(text: "Mic unplugged. Resume will use the MacBook mic.")
        }
    }

    // MARK: - Crash recovery

    /// Anything still marked as recording when the app starts was cut off by a
    /// crash or power loss. Fix the audio file and mark it stopped.
    private func recoverUnfinished() {
        var notices: [String] = []
        for var info in RecordingStore.loadAll() where info.isActive {
            let audio = RecordingStore.wavURL(info.id)
            let samples = (try? WavWriter.repair(audio)) ?? info.samples
            let modified = (try? audio.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let endedAt = modified ?? info.createdAt.addingTimeInterval(info.duration)
            info.samples = samples
            info.state = .stopped
            info.endedAt = endedAt
            info.events.append(.init(kind: .recovered, at: Date(), sample: samples))
            try? RecordingStore.save(info)
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
        try? RecordingStore.save(info)
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
