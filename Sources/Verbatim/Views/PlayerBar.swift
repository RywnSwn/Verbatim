import SwiftUI

/// Under a finished recording's transcript while its audio is open:
/// back 15 s, play/pause, forward 15 s, time, slider, length, speed, close.
/// Plain paper like the bottom bar, no box.
struct PlayerBar: View {
    let info: RecordingInfo
    @State private var dragTime: Double?

    private var player: Playback { .shared }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    iconButton("gobackward.15", help: "Back 15 seconds") { player.skip(-Playback.skipSeconds) }
                    iconButton(player.isPlaying ? "pause.fill" : "play.fill", size: 17,
                               help: player.isPlaying ? "Pause (⌥⌘P)" : "Play (⌥⌘P)") { player.toggle() }
                    iconButton("goforward.15", help: "Forward 15 seconds") { player.skip(Playback.skipSeconds) }
                }

                Text(Playback.clock(dragTime ?? player.time))
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 44, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { dragTime ?? player.time },
                        // Dragging: just move the knob. A plain click: jump there.
                        set: { t in if player.scrubbing { dragTime = t } else { player.seek(to: t) } }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        player.scrubbing = editing
                        if !editing, let t = dragTime {
                            player.seek(to: t)
                            dragTime = nil
                        }
                    }
                )
                .controlSize(.small)
                .accessibilityLabel("Position in the audio")
                .accessibilityValue(Playback.clock(player.time))

                Text(Playback.clock(player.duration))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)

                Menu {
                    ForEach(Playback.speeds, id: \.self) { s in
                        Button {
                            player.speed = s
                        } label: {
                            if s == player.speed {
                                Label(Playback.speedLabel(s), systemImage: "checkmark")
                            } else {
                                Text(Playback.speedLabel(s))
                            }
                        }
                    }
                } label: {
                    Text(Playback.speedLabel(player.speed))
                        .font(.callout.weight(.medium).monospacedDigit())
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Playback speed")
                .accessibilityLabel("Playback speed, \(Playback.speedLabel(player.speed))")

                iconButton("xmark", size: 12, help: "Close the player") { player.close() }
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
        }
        .background(Theme.paper)
    }

    private func iconButton(_ symbol: String, size: CGFloat = 14, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
