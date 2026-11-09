import SwiftUI

/// Timer, waveform, Pause/Stop in the middle, status spot on the right.
/// After Stop it shows "Saved ... Undo Stop" for 10 seconds.
struct BottomBar: View {
    @Environment(RecorderModel.self) private var model

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
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 20)
        }
        .background(.background)
    }

    private var paused: Bool { model.phase == .paused }

    private var recordingBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                Text(RecorderModel.clock(model.elapsed))
                    .font(.system(size: 17, weight: .medium).monospacedDigit())
                    .foregroundStyle(paused ? .secondary : .primary)
                Waveform(levels: model.levels, paused: paused)
                if paused {
                    Text("Paused")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
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
                Text(paused ? "Paused. Nothing is being recorded." : "Saved as you go, works offline")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
    }

    private static func linkTitle(_ action: RecorderModel.Status.Action) -> String {
        switch action {
        case .stopRecording: "Stop recording"
        case .resume: "Resume"
        case .undoDelete: "Undo"
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
