import AppKit
import SwiftUI

extension RecordingInfo {
    /// "English, Mon 10 Nov"
    var fullTitle: String {
        "\(title), \(createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    /// "Started 10:05"
    var startedText: String {
        "Started \(createdAt.formatted(date: .omitted, time: .shortened))"
    }
}

/// Main area while recording: the live text, which is the transcript (step
/// 5c). Words still being worked out are lighter. A plain status line on top
/// only when live text isn't coming from Parakeet.
struct RecordingNowView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(LiveTranscriber.self) private var live
    @Environment(Transcriber.self) private var transcriber
    let info: RecordingInfo

    private var transcript: Transcript? { transcriber.transcripts[info.id] }
    private var checked: [Transcript.Line] { transcript?.lines ?? [] }
    private var lines: [Transcript.Line] {
        live.texts[info.id]?.unchecked(after: transcript?.doneUpTo ?? 0) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            LiveStatusLine(paused: model.phase == .paused)
            FindLine(id: info.id)
            if checked.isEmpty, lines.isEmpty, live.volatile.isEmpty {
                VStack(spacing: 8) {
                    Text(model.phase == .paused ? "Paused." : "Listening.")
                        .font(.title3)
                    Text(emptyNote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TranscriptList(
                    info: info, checked: checked, live: lines, checkedUpTo: transcript?.doneUpTo,
                    volatile: live.volatile, isLive: true
                )
            }
        }
        .navigationTitle(info.fullTitle)
        .navigationSubtitle(info.startedText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.addMarker()
                } label: {
                    Label("Marker", systemImage: "flag")
                }
                .labelStyle(.titleAndIcon)
                .help("Mark this moment, like \"write this down\" (⌘D)")
            }
            ToolbarItem(placement: .primaryAction) {
                ExportMenu(hasLines: !(checked + lines).isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                CopyButton(id: info.id, hasLines: !(checked + lines).isEmpty)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .transcriptSearch()
    }

    private var emptyNote: String {
        if model.phase == .paused { return "Nothing is being recorded. Press Resume to carry on." }
        switch live.status {
        case .listening, .starting, nil: return "Words show up here a couple of seconds after they're said."
        case .off: return "Your audio is being saved. The text comes after you press Stop."
        }
    }
}

/// Says where live text is coming from, only when it isn't the normal case.
struct LiveStatusLine: View {
    @Environment(LiveTranscriber.self) private var live
    let paused: Bool

    var body: some View {
        if let text = message {
            VStack(spacing: 0) {
                HStack {
                    Text(text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private var message: String? {
        guard !paused else { return nil }
        switch live.status {
        case .starting:
            return "Getting live text ready. Your audio is already being saved."
        case .listening(let engine) where engine == AppleSpeechEngine.name:
            if live.isModelReady {
                return "Live text is using your Mac's built-in engine. Parakeet takes over after you pause, and redoes it all after you stop."
            }
            return "Live text is using your Mac's built-in engine until Parakeet finishes downloading\(percentText)."
        case .off(let reason):
            return "No live text right now: \(reason). Your audio is saved, and the text comes after you press Stop."
        default:
            return nil
        }
    }

    private var percentText: String {
        switch live.modelState {
        case .downloading(let f, _), .paused(let f), .failed(let f): " (\(Int(f * 100))%)"
        default: ""
        }
    }
}

/// A finished recording: its transcript, with a plain status line on top while
/// a file is being transcribed. Layout follows docs/design/Transcript.dc.html.
/// Old recordings may still have a Whisper transcript; live text after its
/// end shows under it.
struct PastRecordingView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Transcriber.self) private var transcriber
    @Environment(LiveTranscriber.self) private var live
    let info: RecordingInfo

    private var speakerModel: SpeakerModel { .shared }
    private var playback: Playback { .shared }
    private var playing: Bool { playback.isShowing(info.id) && playback.isPlaying }
    private var transcript: Transcript? { transcriber.transcripts[info.id] }
    private var checked: [Transcript.Line] { transcript?.lines ?? [] }

    /// The live text (minus the part an old Whisper transcript covers).
    private var liveLines: [Transcript.Line] {
        if transcript?.finished == true { return [] }
        return live.texts[info.id]?.unchecked(after: transcript?.doneUpTo ?? 0) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptStatusLine(info: info)
            FindLine(id: info.id)
            if checked.isEmpty, liveLines.isEmpty {
                emptyState
            } else {
                TranscriptList(info: info, checked: checked, live: liveLines, checkedUpTo: transcript?.doneUpTo)
            }
            if playback.isShowing(info.id) {
                PlayerBar(info: info)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: playback.isShowing(info.id))
        .navigationTitle(info.fullTitle)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                if !model.isBusy {
                    Button {
                        model.showNewRecording()
                    } label: {
                        Label("New recording", systemImage: "plus")
                    }
                    .help("New recording (⌘N)")
                }
                Button {
                    if playback.isShowing(info.id) { playback.toggle() } else { model.playAudio(info.id) }
                } label: {
                    Label(playing ? "Pause audio" : "Play audio", systemImage: playing ? "pause.fill" : "play.fill")
                }
                .disabled(!info.hasAudio)
                .help(info.hasAudio ? (playing ? "Pause the audio (⌥⌘P)" : "Play the audio here (⌥⌘P)")
                    : "The audio was deleted. The text is still here.")
                ExportMenu(hasLines: !(checked + liveLines).isEmpty)
                Menu {
                    Button("Show in Finder") { model.showInFinder(info) }
                    Divider()
                    Button("Transcribe again") { transcriber.redo(info.id) }
                        .disabled(!info.hasAudio || transcriber.active?.id == info.id
                            || transcriber.importing.contains(info.id) || transcriber.isGrowing(info.id))
                    Button("Find speakers again") { transcriber.findSpeakers(info.id) }
                        .disabled(!info.hasAudio || !speakerModel.isReady || liveLines.isEmpty
                            || transcriber.active?.id == info.id || transcriber.isFindingSpeakers(info.id)
                            || transcriber.isGrowing(info.id) || transcriber.isUnfinished(info.id))
                    Divider()
                    Button(SidebarView.deleteAudioTitle(info, blocker: model.audioDeleteBlocker(info.id))) {
                        model.deleteAudio(info.id)
                    }
                    .disabled(model.audioDeleteBlocker(info.id) != nil)
                    Button("Move to Trash") { model.delete(info.id) }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Show in Finder, Transcribe again, Find speakers again, Delete audio only, Move to Trash")
            }
            ToolbarItem(placement: .primaryAction) {
                CopyButton(id: info.id, hasLines: !(checked + liveLines).isEmpty)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .transcriptSearch()
    }

    private var subtitle: String {
        if let name = info.importedFrom { return "From \(name), \(RecorderModel.minutesText(info.duration))" }
        return "\(info.startedText), \(RecorderModel.minutesText(info.duration))"
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            Text(info.fullTitle)
                .font(.system(size: 30, weight: .medium, design: .serif))
            if transcript?.finished == true {
                Text("No speech found in this recording.")
                    .foregroundStyle(.secondary)
            } else if !info.hasAudio {
                Text("The audio was deleted before it was transcribed.")
                    .foregroundStyle(.secondary)
            } else if !transcriber.isQueued(info.id), transcriber.active?.id != info.id,
                      !transcriber.importing.contains(info.id), transcriber.errors[info.id] == nil,
                      !transcriber.isUnfinished(info.id) {
                Button("Transcribe") { transcriber.enqueue(info.id) }
                    .buttonStyle(.inkLarge)
            } else {
                Text("Text shows up here as it goes.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A plain line at the top of the transcript saying what is happening, with a
/// text link only when there is something to do. No box.
struct TranscriptStatusLine: View {
    @Environment(Transcriber.self) private var transcriber
    @Environment(LiveTranscriber.self) private var live
    let info: RecordingInfo

    var body: some View {
        if let m = message {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(m.0)
                        .font(.callout)
                        .monospacedDigit()
                    if let link = m.1, let action = m.2 {
                        Button(link, action: action)
                            .buttonStyle(.link)
                            .font(.callout.weight(.medium))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                if let job = transcriber.active, job.id == info.id, job.totalSeconds > 0 {
                    ProgressView(value: min(job.doneSeconds / job.totalSeconds, 1))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                Divider()
            }
        }
    }

    private var message: (String, String?, (() -> Void)?)? {
        let id = info.id
        let original = info.importedFrom == nil ? "" : " Your original file isn't touched."
        // Just stopped (Undo Stop still possible).
        if transcriber.isGrowing(id), transcriber.errors[id] == nil { return nil }
        if transcriber.importing.contains(id) {
            return ("Importing \(info.importedFrom ?? info.title).\(original)", nil, nil)
        }
        if let error = transcriber.errors[id] {
            if !info.hasAudio { return (error, nil, nil) }
            return (error, "Try again", { transcriber.enqueue(id) })
        }
        if let job = transcriber.active, job.id == id, job.speakersOnly {
            var text = "Finding who said what. The text stays as it is."
            if let left = job.secondsLeft { text += " \(Transcriber.leftText(left).capitalizedFirst)." }
            return (text, "Cancel", { transcriber.cancel(id) })
        }
        if transcriber.speakerQueue.contains(id) {
            return ("Finding who said what next, after the files before it.", "Cancel", { transcriber.cancel(id) })
        }
        if let job = transcriber.active, job.id == id {
            let done = Int(job.doneSeconds / 60), total = max(1, Int((job.totalSeconds / 60).rounded(.up)))
            var text = "Transcribing. Text appears as it goes. \(done) of \(total) min"
            if let left = job.secondsLeft { text += ", \(Transcriber.leftText(left))" }
            return (text, "Cancel", { transcriber.cancel(id) })
        }
        if transcriber.isQueued(id) {
            switch live.modelState {
            case .downloading(let f, _), .paused(let f), .failed(let f):
                return ("Waiting for the speech model download to finish (\(Int(f * 100))%).", nil, nil)
            case .preparing:
                return ("Getting the speech model ready. The first time takes a few minutes.", nil, nil)
            case .ready:
                if transcriber.isWaitingForRecording {
                    return ("Waits until you stop recording, then takes about a minute per hour.", "Cancel", { transcriber.cancel(id) })
                }
                return ("Waiting for another file to finish.", "Cancel", { transcriber.cancel(id) })
            }
        }
        let text = live.texts[id]
        if let pass = text?.pass, !pass.finished {
            let minutes = Int(pass.doneUpTo / 60)
            if !info.hasAudio {
                return ("Transcribed the first \(minutes) min. The audio was deleted, so the rest can't be done.", nil, nil)
            }
            return ("Transcribed the first \(minutes) min.", "Continue", { transcriber.enqueue(id) })
        }
        // An old Whisper transcript that stopped halfway, with no text after it.
        if let t = transcriber.transcripts[id], !t.finished, text?.lines.isEmpty ?? true {
            let minutes = Int(t.doneUpTo / 60)
            if !info.hasAudio {
                return ("Transcribed the first \(minutes) min. The audio was deleted, so the rest can't be done.", nil, nil)
            }
            return ("Transcribed the first \(minutes) min.", "Continue", { transcriber.enqueue(id) })
        }
        // Made with the Mac's backup engine before Parakeet was here.
        if text?.pass == nil, text?.madeWithBackupEngine == true, info.hasAudio, live.isModelReady {
            return ("Made with your Mac's built-in engine. Parakeet is more accurate, and your edits are kept.",
                    "Redo with Parakeet", { transcriber.redo(id) })
        }
        return nil
    }
}

/// Mic access is off. Takes over the main area, with a way out.
struct MicBlockedView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Text("Verbatim can't hear anything")
                .font(.system(size: 30, weight: .medium, design: .serif))
            Text("Microphone access is off for Verbatim. Turn it on, then come back.")
                .foregroundStyle(.secondary)
            Button("Open Microphone settings") { model.openMicSettings() }
                .buttonStyle(.inkLarge)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}

/// Cmd+F search in the toolbar. Enter goes to the next hit, Esc clears it.
struct TranscriptSearch: ViewModifier {
    @Environment(RecorderModel.self) private var model
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search transcript")
            .searchFocused($focused)
            .onSubmit(of: .search) { model.nextMatch(1) }
            .onChange(of: model.findRequest) { focused = true }
    }
}

extension View {
    func transcriptSearch() -> some View { modifier(TranscriptSearch()) }
}

/// "2 of 7" with up and down arrows, under the toolbar while searching.
/// A plain line like the other status lines, no box.
struct FindLine: View {
    @Environment(RecorderModel.self) private var model
    let id: UUID

    var body: some View {
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let count = model.searchMatches(id).count
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(count == 0 ? "No matches" : "\(min(model.matchIndex, count - 1) + 1) of \(count)")
                        .font(.callout)
                        .monospacedDigit()
                    if count > 1 {
                        HStack(spacing: 2) {
                            Button { model.nextMatch(-1) } label: {
                                Image(systemName: "chevron.up").frame(width: 24, height: 24)
                            }
                            .help("Previous match (⇧⌘G)")
                            .accessibilityLabel("Previous match")
                            Button { model.nextMatch(1) } label: {
                                Image(systemName: "chevron.down").frame(width: 24, height: 24)
                            }
                            .help("Next match (⌘G or Enter)")
                            .accessibilityLabel("Next match")
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer(minLength: 0)
                    Button("Done") { model.searchText = "" }
                        .buttonStyle(.link)
                        .font(.callout.weight(.medium))
                        .help("Stop searching (Esc in the search field)")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}

extension String {
    /// "about 4 min left" -> "About 4 min left".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
