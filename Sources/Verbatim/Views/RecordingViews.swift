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

/// Main area while recording: checked (accurate) text in full ink, then the
/// live text after it, a little grey. Every 5 minutes the background pass
/// replaces the oldest grey part. A plain status line on top only when live
/// text isn't coming from Parakeet.
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
            ToolbarItemGroup {
                CopyAllButton(lines: checked + lines)
            }
        }
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
                return "Live text is using your Mac's built-in engine. Parakeet takes over after you pause or stop."
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
/// it is being transcribed. Layout follows docs/design/Transcript.dc.html.
/// Until the accurate pass gets to a part, the live text for it shows in grey.
struct PastRecordingView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Transcriber.self) private var transcriber
    @Environment(LiveTranscriber.self) private var live
    let info: RecordingInfo

    private var transcript: Transcript? { transcriber.transcripts[info.id] }
    private var checked: [Transcript.Line] { transcript?.lines ?? [] }

    /// Live lines the accurate pass hasn't reached yet.
    private var liveLines: [Transcript.Line] {
        if transcript?.finished == true { return [] }
        return live.texts[info.id]?.unchecked(after: transcript?.doneUpTo ?? 0) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptStatusLine(info: info)
            if checked.isEmpty, liveLines.isEmpty {
                emptyState
            } else {
                TranscriptList(info: info, checked: checked, live: liveLines, checkedUpTo: transcript?.doneUpTo)
            }
        }
        .navigationTitle(info.fullTitle)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                if !model.isBusy {
                    Button {
                        Task { await model.start() }
                    } label: {
                        Label("New recording", systemImage: "mic")
                    }
                    .help("Start a new recording (⌘R)")
                }
                Menu {
                    Button("Play audio") { NSWorkspace.shared.open(RecordingStore.audioURL(info.id)) }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([RecordingStore.audioURL(info.id)])
                    }
                    Divider()
                    Button("Transcribe again") { transcriber.redo(info.id) }
                        .disabled(transcriber.active?.id == info.id || transcriber.importing.contains(info.id)
                            || transcriber.isGrowing(info.id))
                    Divider()
                    Button("Move to Trash") { model.delete(info.id) }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Play audio, Show in Finder, Transcribe again, Move to Trash")

                CopyAllButton(lines: checked + liveLines)
            }
        }
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
            } else if transcript == nil, !transcriber.isQueued(info.id), transcriber.active?.id != info.id,
                      !transcriber.importing.contains(info.id), transcriber.errors[info.id] == nil {
                Button("Transcribe") { transcriber.enqueue(info.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
        // Just stopped (Undo Stop still possible): the rest is checked in a moment.
        if transcriber.isGrowing(id), transcriber.errors[id] == nil { return nil }
        if transcriber.importing.contains(id) {
            return ("Importing \(info.importedFrom ?? info.title).\(original)", nil, nil)
        }
        if let error = transcriber.errors[id] {
            return (error, "Try again", { transcriber.enqueue(id) })
        }
        if let job = transcriber.active, job.id == id {
            let done = Int(job.doneSeconds / 60), total = max(1, Int((job.totalSeconds / 60).rounded(.up)))
            var text = "Transcribing. Text appears as it goes. \(done) of \(total) min"
            if let left = job.secondsLeft { text += ", \(Transcriber.leftText(left))" }
            return (text, "Cancel", { transcriber.cancel(id) })
        }
        if transcriber.isQueued(id) {
            switch transcriber.modelState {
            case .downloading(let f, _), .paused(let f), .failed(let f):
                return ("Waiting for the model download to finish (\(Int(f * 100))%).", nil, nil)
            case .preparing:
                return ("Getting the model ready. The first time takes a few minutes.", nil, nil)
            case .ready:
                return ("Waiting for another recording to finish.", "Cancel", { transcriber.cancel(id) })
            }
        }
        if let t = transcriber.transcripts[id], !t.finished {
            let minutes = Int(t.doneUpTo / 60)
            return ("Transcribed the first \(minutes) min.", "Continue", { transcriber.enqueue(id) })
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
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}
