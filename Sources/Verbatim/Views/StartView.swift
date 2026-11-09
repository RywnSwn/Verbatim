import AVFoundation
import SwiftUI

/// First launch / empty screen. Layout follows docs/design/Empty.dc.html.
struct StartView: View {
    @Environment(RecorderModel.self) private var model

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
                    Task { await model.start() }
                } label: {
                    HStack(spacing: 10) {
                        Text("Start recording")
                        Text("⌘R").foregroundStyle(Theme.paper.opacity(0.65))
                    }
                }
                .buttonStyle(.inkLarge)

                Text("Or drop a Voice Memo here to transcribe it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.bottom, 18)
                VStack(alignment: .leading, spacing: 16) {
                    MicStatusLine(permission: model.micPermission, micName: model.micName)
                    LiveModelStatusLine()
                    ModelStatusLine()
                }
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

/// Under the thin line: is the mic ready, and which one.
struct MicStatusLine: View {
    let permission: AVAuthorizationStatus
    let micName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: permission == .authorized ? "checkmark" : "mic")
                .fontWeight(.semibold)
                .foregroundStyle(permission == .authorized ? Color.green : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission == .authorized ? "Microphone allowed" : "Microphone")
                    .font(.body.weight(.medium))
                Text(permission == .authorized
                     ? "Using the \(micName). Change it in Settings (⌘,)."
                     : "Your Mac asks to use the mic the first time you press Start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Version \(AppInfo.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "dev"
    }
}

/// The accurate model: downloading, paused, getting ready, or ready.
struct ModelStatusLine: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: transcriber.isModelReady ? "checkmark" : "arrow.down")
                .fontWeight(.semibold)
                .foregroundStyle(transcriber.isModelReady ? Color.green : Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch transcriber.modelState {
        case .ready:
            title("Accurate model ready")
            note("After you press Stop, it checks the whole recording again more carefully. Works offline.")
        case .preparing:
            title("Getting the model ready")
            note("First time only, this can take a few minutes. Keep Verbatim open.")
        case .downloading(let fraction, let left):
            HStack {
                title("Downloading accurate model")
                Spacer()
                Text(Self.progressText(fraction, left))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
            note("One time only. If the internet drops, it picks up where it left off. You can record now: the text comes once this finishes.")
            Button("Pause download") { transcriber.pauseDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        case .paused(let fraction):
            title("Download paused at \(Int(fraction * 100))%")
            Button("Resume download") { transcriber.startDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        case .failed(let fraction):
            title("Download stopped at \(Int(fraction * 100))%")
            note("Probably the internet. Trying again by itself every 20 seconds.")
            Button("Try now") { transcriber.startDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        }
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.body.weight(.medium))
    }

    private func note(_ s: String) -> some View {
        Text(s)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func progressText(_ fraction: Double, _ left: Double?) -> String {
        let percent = "\(Int(fraction * 100))% of \(WhisperEngine.sizeText)"
        guard let left, left.isFinite else { return percent }
        return "\(percent), \(Transcriber.leftText(left))"
    }
}

/// The live model (Parakeet): downloading, paused, getting ready, or ready.
struct LiveModelStatusLine: View {
    @Environment(LiveTranscriber.self) private var live

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: live.isModelReady ? "checkmark" : "arrow.down")
                .fontWeight(.semibold)
                .foregroundStyle(live.isModelReady ? Color.green : Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch live.modelState {
        case .ready:
            title("Live text ready")
            note("Words show up a couple of seconds after they're said. Works offline.")
        case .preparing:
            title("Getting live text ready")
            note("First time only, this can take a few minutes. Keep Verbatim open.")
        case .downloading(let fraction, let left):
            HStack {
                title("Downloading live text model")
                Spacer()
                Text(Self.progressText(fraction, left))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
            note("One time only, picks up where it left off. Until it's done, live text uses your Mac's built-in speech engine.")
            Button("Pause download") { live.pauseDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        case .paused(let fraction):
            title("Live text download paused at \(Int(fraction * 100))%")
            Button("Resume download") { live.startDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        case .failed(let fraction):
            title("Live text download stopped at \(Int(fraction * 100))%")
            note("Probably the internet. Trying again by itself every 20 seconds.")
            Button("Try now") { live.startDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        }
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.body.weight(.medium))
    }

    private func note(_ s: String) -> some View {
        Text(s)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func progressText(_ fraction: Double, _ left: Double?) -> String {
        let percent = "\(Int(fraction * 100))% of \(ParakeetEngine.sizeText)"
        guard let left, left.isFinite else { return percent }
        return "\(percent), \(Transcriber.leftText(left))"
    }
}
