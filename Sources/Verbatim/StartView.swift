import SwiftUI

/// First launch / empty screen. Layout follows docs/design/Empty.dc.html.
/// Step 1 is only the skeleton: the Start button is shown but not wired up yet.
struct StartView: View {
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 26) {
                VStack(spacing: 0) {
                    Text("Hear it once.")
                        .font(.system(size: 54, weight: .medium, design: .serif))
                    Text("Keep every word.")
                        .font(.system(size: 54, weight: .regular, design: .serif))
                        .italic()
                }
                .multilineTextAlignment(.center)

                WaveToWords()
                    .frame(width: 620, height: 40)
                    .accessibilityHidden(true)

                Button {
                } label: {
                    Text("Start recording")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .padding(.bottom, 12)
                Text("Test build")
                    .font(.body.weight(.medium))
                Text("Verbatim installs and opens. Recording comes in the next update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Version \(AppInfo.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(width: 460, alignment: .leading)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The signature: grey bars while someone talks, dots when quiet,
/// and the words appearing next to it.
struct WaveToWords: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let line = "\u{201C}Anansi has just made his deal with Nyankupon, the sky god. Write this down.\u{201D}"
    private let barCount = 22
    private let tick = 0.07

    var body: some View {
        TimelineView(.animation(minimumInterval: tick, paused: reduceMotion)) { context in
            let frame = reduceMotion
                ? line.count
                : Int(context.date.timeIntervalSinceReferenceDate / tick) % (line.count + 30)
            let talking = !reduceMotion && frame < line.count

            HStack(spacing: 14) {
                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let h = barHeight(index: i, frame: frame, talking: talking)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(h > 3 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 3, height: h)
                    }
                }
                .frame(height: 40)

                Text(String(line.prefix(min(frame, line.count))))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
    }

    private func barHeight(index i: Int, frame t: Int, talking: Bool) -> CGFloat {
        guard talking else { return 3 }
        let wave = abs(sin(Double(t) * 0.45 + Double(i) * 0.9))
        let scale = 0.4 + Double(i % 5) / 6
        return 4 + (wave * 30 * scale).rounded()
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "dev"
    }
}
