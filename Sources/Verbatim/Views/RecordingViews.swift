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

/// Main area while recording. The live transcript replaces this in step 4.
struct RecordingNowView: View {
    let info: RecordingInfo

    var body: some View {
        VStack(spacing: 8) {
            Text("Live text comes in a later update.")
                .font(.title3)
            Text("The text for this recording appears 10 seconds after you press Stop.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .navigationTitle(info.fullTitle)
        .navigationSubtitle(info.startedText)
    }
}

/// A finished recording: its transcript, with a plain status line on top while
/// it is being transcribed. Layout follows docs/design/Transcript.dc.html.
struct PastRecordingView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Transcriber.self) private var transcriber
    let info: RecordingInfo
    @State private var copiedLabel: String?

    private var transcript: Transcript? { transcriber.transcripts[info.id] }
    private var lines: [Transcript.Line] { transcript?.lines ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptStatusLine(info: info)
            if lines.isEmpty {
                emptyState
            } else {
                transcriptList
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
                        .disabled(transcriber.active?.id == info.id || transcriber.importing.contains(info.id))
                    Divider()
                    Button("Move to Trash") { model.delete(info.id) }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Play audio, Show in Finder, Transcribe again, Move to Trash")

                Button(copiedLabel ?? "Copy all") { copyAll() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(lines.isEmpty)
                    .help(lines.isEmpty ? "Nothing to copy yet" : "Copy the whole transcript (⇧⌘C)")
            }
        }
    }

    private var subtitle: String {
        if let name = info.importedFrom { return "From \(name), \(RecorderModel.minutesText(info.duration))" }
        return "\(info.startedText), \(RecorderModel.minutesText(info.duration))"
    }

    private var transcriptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(timeLabel(line.start))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                        Text(line.text)
                            .font(.system(size: 15))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
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

    /// Clock time (10:42) for recordings, time since start (37:12) for imported files.
    private func timeLabel(_ seconds: Double) -> String {
        if info.importedFrom != nil {
            let s = Int(seconds)
            return s >= 3600
                ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
        return info.wallTime(atSecond: seconds).formatted(.dateTime.hour().minute())
    }

    private func copyAll() {
        guard let transcript, !transcript.lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.plainText, forType: .string)
        let label = "Copied \(transcript.lines.count) lines"
        copiedLabel = label
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedLabel == label { copiedLabel = nil }
        }
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
        let original = info.importedFrom.map { " Your original file isn't touched." } ?? ""
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
