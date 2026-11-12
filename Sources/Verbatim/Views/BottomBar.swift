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
                    undoBar("Moved \(note.info.title) to Recently deleted.", undo: "Undo") { model.undoDelete() }
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
            // Grows for a long message in a narrow window instead of spilling
            // past the window's rounded bottom edge. Extra side room clears the corners.
            .frame(minHeight: 56)
            .padding(.vertical, 6)
            .padding(.horizontal, 24)
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
                    // No rolling digits here (see the note on Waveform).
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
        ZStack(alignment: .trailing) {
            statusContent
                .id(model.status?.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)))
        }
        .clipped()
        .animation(.snappy(duration: 0.3), value: model.status?.id)
    }

    /// New messages slide up into place and old ones slide away.
    private var statusContent: some View {
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
        .lineLimit(3)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The normal message when nothing needs attention.
    private var quietText: String {
        if paused { return "Paused. Nothing is being recorded." }
        return "Saved as you go, works offline"
    }

    static func linkTitle(_ action: RecorderModel.Status.Action) -> String {
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
            Spacer(minLength: 0)
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Button(undo, action: action)
                .buttonStyle(.link)
                .font(.callout.weight(.medium))
                .fixedSize() // the link never wraps or gets cut
        }
    }
}

/// The signature waveform: grey bars when someone talks, grey dots when quiet. No color.
///
/// Drawn as ONE picture (a Canvas). It used to be 40 separate shapes that
/// each changed 20 times a second, plus rolling digits on the timers. On
/// macOS 26 every changing piece is its own drawing surface, and when many
/// change at once the app's main thread waits for the screen to catch up
/// (RenderBox: SharedSurfaceGroup add_subsurface, wait_for_allocations).
/// That froze the timer, the bars and live text until Pause: the real cause
/// of "lag while recording" (found 2026-11-12 with Ryan's stall sample).
/// Rule: anything that moves while recording is one Canvas or plain text.
/// No shape per bar, no `.contentTransition(.numericText())`, no
/// `.symbolEffect` that repeats.
struct Waveform: View {
    let levels: [Float]
    let paused: Bool

    var body: some View {
        Canvas { context, size in
            for (i, level) in levels.enumerated() {
                let quiet = paused || level < 0.15
                let height: CGFloat = quiet ? 3 : 3 + CGFloat(level) * 24
                let rect = CGRect(x: CGFloat(i) * 6, y: (size.height - height) / 2, width: 3, height: height)
                let path = Path(roundedRect: rect, cornerRadius: 1.5)
                if quiet {
                    context.fill(path, with: .style(.tertiary))
                } else {
                    context.fill(path, with: .style(.secondary))
                }
            }
        }
        .frame(width: max(3, CGFloat(levels.count) * 6 - 3), height: 28)
        .accessibilityElement()
        .accessibilityLabel(paused ? "Paused, not listening" : "Listening")
    }
}
