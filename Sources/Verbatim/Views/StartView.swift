import AVFoundation
import SwiftUI

/// First launch / empty screen. Layout follows docs/design/Empty.dc.html.
struct StartView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        // Fits: centered. Window too short: it scrolls instead of being cut off.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content.frame(maxWidth: .infinity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                WaveToWords()
                    .frame(minWidth: 300, maxWidth: 620)
                    .frame(height: 40)
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
                }
            }
            .frame(minWidth: 300, maxWidth: 460, alignment: .leading)
        }
        .padding(40)
    }
}

/// The signature: grey bars while someone talks, dots when quiet,
/// and the words appearing next to it. Speech eases in and out, pauses a
/// moment at commas and full stops, and the words fade before it repeats.
struct WaveToWords: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let line = "\u{201C}Anansi has just made his deal with Nyankupon, the sky god. Write this down.\u{201D}"
    private static let charTime = 0.065
    private static let punctuationPause = 0.45
    private static let hold = 1.8, fade = 0.6, rest = 0.7
    private let barCount = 22

    /// When each character appears, and the stretches of time with talking.
    private static let schedule: (times: [Double], talking: [ClosedRange<Double>], end: Double) = {
        var times: [Double] = []
        var talking: [ClosedRange<Double>] = []
        var t = 0.3, segmentStart = t
        for ch in line {
            times.append(t)
            t += charTime
            if ch == "," || ch == "." {
                talking.append(segmentStart...t)
                t += punctuationPause
                segmentStart = t
            }
        }
        if segmentStart < t { talking.append(segmentStart...t) }
        return (times, talking, t)
    }()

    private static var cycle: Double { schedule.end + hold + fade + rest }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? Self.schedule.end + 0.1 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            let shown = Self.schedule.times.filter { $0 <= t }.count
            let wordsOpacity = textOpacity(at: t)
            let level = loudness(at: t)

            HStack(spacing: 14) {
                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let h = barHeight(index: i, time: t, loudness: level)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(h > 4 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 3, height: h)
                    }
                }
                .frame(height: 40)

                Text(String(Self.line.prefix(shown)))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .opacity(wordsOpacity)
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

    /// 0 when quiet, 1 mid-sentence, easing in and out at each pause.
    private func loudness(at t: Double) -> Double {
        var best = 0.0
        for seg in Self.schedule.talking {
            let rise = smooth((t - seg.lowerBound) / 0.25)
            let fall = smooth((seg.upperBound + 0.1 - t) / 0.35)
            best = max(best, min(rise, fall))
        }
        return best
    }

    private func textOpacity(at t: Double) -> Double {
        let fadeStart = Self.schedule.end + Self.hold
        if t < fadeStart { return 1 }
        return 1 - smooth((t - fadeStart) / Self.fade)
    }

    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    private func barHeight(index i: Int, time t: Double, loudness: Double) -> CGFloat {
        let wave = abs(sin(t * 6.3 + Double(i) * 0.9)) * (0.6 + 0.4 * abs(sin(t * 2.1 + Double(i) * 0.37)))
        let scale = 0.4 + Double(i % 5) / 6
        return 3 + (wave * 30 * scale * loudness).rounded()
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

/// The Parakeet model (live text and files): downloading, paused, getting ready, or ready.
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
            title("Speech model ready")
            note("Words show up a couple of seconds after they're said. A Voice Memo takes about a minute per hour. Works offline.")
            SpeakerModelNote()
            WordModelNote()
        case .preparing:
            title("Getting the speech model ready")
            note("First time only, this can take a few minutes. Keep Verbatim open.")
        case .downloading(let fraction, let left):
            HStack {
                title("Downloading the speech model")
                Spacer()
                Text(Self.progressText(fraction, left))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
            note("One time only, picks up where it left off. Until it's done, live text uses your Mac's built-in speech engine, and Voice Memos wait.")
            Button("Pause download") { live.pauseDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        case .paused(let fraction):
            title("Download paused at \(Int(fraction * 100))%")
            Button("Resume download") { live.startDownload() }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
        case .failed(let fraction):
            title("Download stopped at \(Int(fraction * 100))%")
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

/// Under "Speech model ready": the speaker model (step 7), which comes after.
/// Nothing shows once it's ready, since there's nothing to do.
struct SpeakerModelNote: View {
    private var speakers: SpeakerModel { .shared }

    var body: some View {
        switch speakers.state {
        case .ready, .waiting:
            EmptyView()
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Downloading speaker labels")
                    Spacer()
                    Text("\(Int(f * 100))% of \(SpeakerEngine.sizeText)").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView(value: f)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                Text("You can record now. Lines get speakers once this is done, on old recordings too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        case .preparing:
            Text("Getting speaker labels ready. First time only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let f):
            HStack(spacing: 8) {
                Text("Speaker labels download stopped at \(Int(f * 100))%. Trying again by itself.")
                Button("Try now") { speakers.startIfNeeded() }
                    .buttonStyle(.link)
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// The word spotter (step 8), after the speaker model. On the start screen it
/// only shows while something is happening; in Settings > Words it always says
/// where things stand.
struct WordModelNote: View {
    var inSettings = false
    private var model: WordModel { .shared }

    var body: some View {
        switch model.state {
        case .ready:
            if inSettings { line("Listening for these words. Changes count from the next recording, or after Pause.") }
        case .waiting:
            if inSettings {
                line(WordList.shared.words.isEmpty
                     ? "Add a word and Verbatim downloads what it needs to listen for it (\(ParakeetEngine.wordSpotterSizeText), one time)."
                     : "Downloads by itself (\(ParakeetEngine.wordSpotterSizeText), one time) once the speech model and speaker labels are here. Fixes work already.")
            }
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Downloading the word list helper")
                    Spacer()
                    Text("\(Int(f * 100))% of \(ParakeetEngine.wordSpotterSizeText)").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView(value: f)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                line("You can record now. Names from the word list get listened for once this is done. Fixes work already.")
            }
            .padding(.top, 2)
        case .preparing:
            line("Getting the word list ready. First time only.")
        case .failed(let f):
            HStack(spacing: 8) {
                Text("Word list download stopped at \(Int(f * 100))%. Trying again by itself.")
                Button("Try now") { model.startIfNeeded() }
                    .buttonStyle(.link)
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func line(_ s: String) -> some View {
        Text(s)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
