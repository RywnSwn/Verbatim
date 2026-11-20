import AVFoundation
import Speech
import SwiftUI

/// The start screen (2026-11-18, Ryan picked "E, a blank notebook page"):
/// the first page of the class, still empty. The group is the page title
/// (click it to pick another), the date and mic sit under it, Record is on
/// the right, and the page below says where the words will appear. No
/// greeting and no box in the middle, so it doesn't look like an AI chat.
/// Mockup: https://claude.ai/artifact/Bx3y11h4r3KMAz1s9EnCbh
struct StartView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(LiveTranscriber.self) private var live

    /// Scrolls when the window is short. Without this the screen was taller
    /// than a short window, which pushed the sidebar's top and bottom past
    /// the window's edges (Ryan's screenshot).
    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                page
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    // The drop hint sits at the bottom of the window, or
                    // under the page when the window is short.
                    .overlay(alignment: .bottom) {
                        Text("Or drop a Voice Memo here to transcribe it.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 20)
                            .frame(maxWidth: .infinity)
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Get the live models ready while you're on this page, so Record
        // starts listening straight away (see LiveTranscriber.warmUp).
        .onAppear { live.warmUp() }
        // Until Parakeet is here, live text uses the Mac's own engine, which
        // needs Speech Recognition access. Ask now, not the first time Record
        // is pressed in class (B12). Only once the mic is allowed, so the two
        // questions don't come at once.
        .task {
            if !live.isModelReady, model.micPermission == .authorized,
               SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                _ = await AppleSpeechEngine.authorize()
            }
        }
        .onChange(of: live.modelState == .ready) { if live.modelState == .ready { live.warmUp() } }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wide window: title left, Record right. Narrow: Record under it.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    titleBlock
                    Spacer(minLength: 0)
                    recordButton
                }
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    recordButton
                }
            }
            .padding(.bottom, 14)

            // Same rule and the same space around it as a transcript's
            // header (RecordingHeader): 14 above, 24 to the first line.
            Rectangle()
                .fill(Theme.rule)
                .frame(height: 1)
                .accessibilityHidden(true)
                .padding(.bottom, 24)

            // The hint sits where the first line will be. The model status
            // goes under it, so an empty status can't add a gap above it.
            VStack(alignment: .leading, spacing: 12) {
                Text("The class shows up on this page as it's said.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                PageModelStatus()
            }
        }
        // Same spot as a transcript's header (TranscriptList: 32 side
        // margin, 24 top), so pressing Record doesn't move the title, the
        // rule or the hint. Starts at the page edge, not 70 pt in past the
        // time gutter: there are no times here, and Ryan found that gap too
        // big (2026-11-19).
        .padding(.top, 24)
        .padding(.bottom, 64) // room for the drop hint
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Like a transcript's header: small line on top, big title,
            // then details.
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            GroupTitleMenu()
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        model.micPermission == .authorized
            ? "Using the \(model.micName)."
            : "Your Mac asks to use the mic when you press Record."
    }

    private var recordButton: some View {
        Button {
            Task { await model.start() }
        } label: {
            HStack(spacing: 10) {
                SmallWave()
                Text("Record")
                Text("⌘R").opacity(0.7)
            }
        }
        .buttonStyle(RecordButtonStyle())
        .disabled(model.isBusy)
        .help("Start recording into \(GroupStore.shared.group(GroupStore.shared.lastUsedID)?.name ?? "Recents") (⌘R)")
    }
}

/// The page title: the group the next recording goes into. Clicking it
/// opens the list of groups, like "Save in" used to.
struct GroupTitleMenu: View {
    @Environment(RecorderModel.self) private var model
    private var store: GroupStore { .shared }
    @State private var hovering = false

    var body: some View {
        let current = store.group(store.lastUsedID)
        Menu {
            ForEach(store.groups) { group in
                Button {
                    store.lastUsedID = group.id
                } label: {
                    Label(group.name, systemImage: group.id == current?.id ? "checkmark" : (group.icon ?? "folder"))
                }
            }
            if !store.groups.isEmpty { Divider() }
            Button {
                store.lastUsedID = nil
            } label: {
                Label("Recents (no group)", systemImage: current == nil ? "checkmark" : "clock")
            }
            Button("New Group…") { model.startNewGroup(forNext: true) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(current?.name ?? "Recents")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.ink.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.leading, -6) // the hover box sits outside the text, so the text lines up
        .onHover { hovering = $0 }
        .help("Pick the class this recording goes into")
        .accessibilityLabel("Save in \(current?.name ?? "Recents"). Pick a group")
    }
}

/// The Record button: filled with the Mac's own accent color (Ryan's pick),
/// the one you set in System Settings > Appearance, not Verbatim's blue.
struct RecordButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlAccentColor).opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

/// Verbatim's five-bar wave, small, as the Record button's icon.
struct SmallWave: View {
    private static let heights: [CGFloat] = [6, 10, 14, 10, 6]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().frame(width: 2.5, height: Self.heights[i])
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// The speech model on the start page: nothing once it's ready, one thin
/// bar with Pause while it downloads, one line otherwise. The speaker and
/// word helpers that come after only show while they download.
struct PageModelStatus: View {
    @Environment(LiveTranscriber.self) private var live

    var body: some View {
        switch live.modelState {
        case .ready:
            VStack(alignment: .leading, spacing: 8) {
                SpeakerModelNote()
                WordModelNote()
            }
        case .preparing:
            note("Getting the speech model ready. First time only, this can take a few minutes. Keep Verbatim open.")
        case .downloading(let fraction, let left):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Getting the speech model (1 of 3), first time only")
                    Spacer()
                    Text(LiveModelStatusLine.progressText(fraction, left)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(Theme.ink)
                HStack(alignment: .firstTextBaseline) {
                    note("You can record now. Until it's done, live text uses your Mac's own speech engine, and Voice Memos wait. Then speaker labels and the word list helper (about 100 MB each) come by themselves.")
                    Spacer()
                    Button("Pause") { live.pauseDownload() }
                        .controlSize(.small)
                }
            }
        case .paused(let fraction):
            HStack(alignment: .firstTextBaseline) {
                note("Speech model download paused at \(Int(fraction * 100))%.")
                Spacer()
                Button("Resume") { live.startDownload() }
                    .controlSize(.small)
            }
        case .failed(let fraction):
            HStack(alignment: .firstTextBaseline) {
                note("Speech model download stopped at \(Int(fraction * 100))%, probably the internet. Trying again by itself.")
                Spacer()
                Button("Try Now") { live.startDownload() }
                    .controlSize(.small)
            }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                    Text("Downloading speaker labels (2 of 3)")
                    Spacer()
                    Text("\(Int(f * 100))% of \(SpeakerEngine.sizeText)").monospacedDigit()
                    Button("Pause") { speakers.pause() }
                        .buttonStyle(.link)
                        .fontWeight(.medium)
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
        case .paused(let f):
            HStack(spacing: 8) {
                Text("Speaker labels download paused at \(Int(f * 100))%.")
                Button("Resume") { speakers.resume() }
                    .buttonStyle(.link)
                    .fontWeight(.medium)
            }
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
                    Text("Downloading the word list helper (3 of 3)")
                    Spacer()
                    Text("\(Int(f * 100))% of \(ParakeetEngine.wordSpotterSizeText)").monospacedDigit()
                    Button("Pause") { model.pause() }
                        .buttonStyle(.link)
                        .fontWeight(.medium)
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
        case .paused(let f):
            HStack(spacing: 8) {
                Text("Word list helper download paused at \(Int(f * 100))%.")
                Button("Resume") { model.resume() }
                    .buttonStyle(.link)
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
