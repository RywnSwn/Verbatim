import AppKit
import SwiftUI

/// Timer, waveform, Pause/Stop in the middle, status spot on the right.
/// After Stop it shows "Saved ... Undo Stop" for 10 seconds.
struct BottomBar: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Updater.self) private var updater

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if model.isBusy {
                    recordingBar
                } else if let note = model.stoppedNote {
                    undoBar(note.text, undo: "Undo Stop") { model.undoStop() }
                } else if let note = model.deletedNote {
                    undoBar("Moved \(note.info.title) to the Trash.", undo: "Undo") { model.undoDelete() }
                } else if let status = model.status {
                    if let action = status.action {
                        undoBar(status.text, undo: Self.linkTitle(action)) { model.perform(action) }
                    } else {
                        undoBar(status.text, undo: "OK") { model.clearStatus() }
                    }
                } else if case .ready(let version) = updater.state {
                    if let problem = updater.installProblem {
                        undoBar("Version \(version) is ready. \(problem)", undo: "Show app") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    } else {
                        undoBar("Version \(version) is ready.", undo: "Restart to update") { updater.installAndRestart() }
                    }
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 20)
        }
        .background(Theme.paper)
    }

    private var paused: Bool { model.phase == .paused }

    private var recordingBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                // The timer never shrinks or wraps (Ryan saw "00:0..." in a narrow
                // window); the waveform gives up room instead, keeping the newest bars.
                Text(RecorderModel.clock(model.elapsed))
                    .font(.system(size: 17, weight: .medium).monospacedDigit())
                    .foregroundStyle(paused ? .secondary : .primary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
                Waveform(levels: model.levels, paused: paused)
                    .fixedSize()
                    .frame(minWidth: 0, maxWidth: 240, alignment: .trailing)
                    .clipped()
                if paused {
                    Text("Paused")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(paused ? "Resume" : "Pause") { model.togglePause() }
                    .help(paused ? "Resume (⇧⌘P)" : "Pause (⇧⌘P)")
                Button("Stop") { model.stop() }
                    .help("Stop and save (⌘R)")
            }
            .controlSize(.large)
            .fixedSize()
            .layoutPriority(3)

            statusSpot
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var statusSpot: some View {
        HStack(spacing: 6) {
            if let status = model.status {
                Text(status.text)
                    .foregroundStyle(.primary)
                if let action = status.action {
                    Button(Self.linkTitle(action)) {
                        model.perform(action)
                    }
                    .buttonStyle(.link)
                    .fontWeight(.medium)
                }
            } else {
                Text(quietText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
    }

    /// The normal message when nothing needs attention.
    private var quietText: String {
        if paused { return "Paused. Nothing is being recorded." }
        return "Saved as you go, works offline"
    }

    private static func linkTitle(_ action: RecorderModel.Status.Action) -> String {
        switch action {
        case .stopRecording: "Stop recording"
        case .resume: "Resume"
        case .undoDelete, .undoLine, .undoAudioDelete: "Undo"
        case .showFile: "Show in Finder"
        case .changeVoice: "Change them too"
        }
    }

    private func undoBar(_ text: String, undo: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Spacer()
            Text(text)
                .font(.callout)
            Button(undo, action: action)
                .buttonStyle(.link)
                .font(.callout.weight(.medium))
        }
    }
}

/// The signature waveform: grey bars when someone talks, grey dots when quiet. No color.
struct Waveform: View {
    let levels: [Float]
    let paused: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                if paused || level < 0.15 {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 3, height: 3)
                } else {
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 3, height: 3 + CGFloat(level) * 24)
                }
            }
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(paused ? "Paused, not listening" : "Listening")
    }
}
