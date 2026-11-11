import AVFoundation
import SwiftUI

/// First launch / empty screen. Layout follows docs/design/Empty.dc.html.
struct StartView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 26) {
                // Simple and warm, like Claude's start screen (Ryan, step 10):
                // the waveform mark and a greeting for the time of day.
                HStack(alignment: .center, spacing: 16) {
                    WaveMark()
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    Text(Greeting.text())
                        .font(.system(size: 46, weight: .regular, design: .serif))
                }
                .padding(.bottom, 6)

                Button {
                    Task { await model.start() }
                } label: {
                    HStack(spacing: 10) {
                        Text("Start recording")
                        Text("⌘R").foregroundStyle(Theme.paper.opacity(0.65))
                    }
                }
                .buttonStyle(.inkLarge)

                GroupChooser()

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
            .frame(width: 460, alignment: .leading)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Evening, Ryan". The first name comes from the Mac's account name.
enum Greeting {
    static func text(at date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let name = first.isEmpty ? "" : ", \(first)"
        switch hour {
        case 5..<12: return "Morning\(name)"
        case 12..<17: return "Afternoon\(name)"
        case 17..<22: return "Evening\(name)"
        default: return first.isEmpty ? "Up late?" : "Up late, \(first)?"
        }
    }
}

/// Verbatim's mark: five ink bars, the signature waveform, breathing gently.
/// Still when Reduce Motion is on.
struct WaveMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let rest: [Double] = [0.38, 0.7, 1, 0.7, 0.38]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    let move = reduceMotion ? 0 : 0.18 * sin(t * 1.6 + Double(i) * 0.9)
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: 5, height: 40 * min(1, max(0.2, Self.rest[i] + move)))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// "Save in: English 2026". Remembers the last pick, so the next class
/// starts in the same group with one click.
struct GroupChooser: View {
    @Environment(RecorderModel.self) private var model
    private var store: GroupStore { .shared }

    var body: some View {
        if !store.groups.isEmpty {
            @Bindable var store = store
            HStack(spacing: 6) {
                Text("Save in")
                    .foregroundStyle(.secondary)
                Picker("Save in", selection: $store.lastUsedID) {
                    ForEach(store.groups) { group in
                        Label {
                            Text(group.name)
                        } icon: {
                            Image(systemName: group.icon ?? "folder")
                        }
                        .tag(Optional(group.id))
                    }
                    Divider()
                    Text("Recents (no group)").tag(UUID?.none)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .font(.callout)
        }
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
