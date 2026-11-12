import AVFoundation
import SwiftUI

/// Settings (design pass, 2026-11-12): pages down the left like System
/// Settings, instead of tabs across the top. Every page is a grouped form:
/// a name and a short explanation on the left, the control on the right.
/// General, Look (new), Transcription (step 10), Words (step 8), Voices
/// (step 7c), Storage (step 9), Updates, Shortcuts (new).
struct SettingsView: View {
    @State private var page: SettingsPage? = .general
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SidebarLook.key) private var sidebarLook: SidebarLook = .glass

    private var solid: Bool { sidebarLook == .solid || reduceTransparency }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { p in
                Label(p.title, systemImage: p.icon)
                    .tag(p)
            }
            .scrollContentBackground(solid ? .hidden : .automatic)
            .background {
                if solid { Theme.sidebarSolid.ignoresSafeArea() }
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch page ?? .general {
                case .general: GeneralSettings()
                case .look: LookSettings()
                case .transcription: TranscriptionSettings()
                case .words: WordSettings()
                case .voices: VoiceSettings()
                case .claude: ClaudeSettings()
                case .storage: StorageSettings()
                case .updates: UpdateSettings()
                case .shortcuts: ShortcutSettings()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((page ?? .general).title)
        }
        .frame(width: 740, height: 560)
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, look, transcription, words, voices, claude, storage, updates, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .look: "Look"
        case .transcription: "Transcription"
        case .words: "Words"
        case .voices: "Voices"
        case .claude: "Claude"
        case .storage: "Storage"
        case .updates: "Updates"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .look: "eye"
        case .transcription: "text.word.spacing"
        case .words: "character.book.closed"
        case .voices: "person.wave.2"
        case .claude: "bubble.left.and.text.bubble.right"
        case .storage: "internaldrive"
        case .updates: "arrow.down.circle"
        case .shortcuts: "keyboard"
        }
    }
}

/// The top of a settings page: what the page is for, then the first group's
/// name. Used as the first section's header, so it scrolls with the page.
struct PageHeader: View {
    let lede: String
    var first: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lede)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let first {
                // Same look as the other section names on the page.
                Text(first)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeneralSettings: View {
    @Environment(RecorderModel.self) private var model
    @AppStorage(Microphones.chosenKey) private var chosenID = ""
    @AppStorage(RecorderModel.quietMinutesKey) private var quietMinutes = 5
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage(Messages.enabledKey) private var messagesOn = true
    @State private var mics: [Mic] = []

    var body: some View {
        Form {
            Section {
                Picker(selection: $chosenID) {
                    Text("MacBook mic (recommended)").tag("")
                    ForEach(mics.filter { !$0.isBuiltIn }) { mic in
                        Text(mic.displayName).tag(mic.id)
                    }
                    if !chosenID.isEmpty, !mics.contains(where: { $0.id == chosenID }) {
                        Text("Unplugged mic").tag(chosenID)
                    }
                } label: {
                    Text("Microphone")
                    Text(micHelp)
                }
            } header: {
                PageHeader(lede: "Your mic, and how Verbatim gets your attention.")
            }

            Section("While recording") {
                Picker(selection: $quietMinutes) {
                    Text("After 5 minutes of quiet").tag(5)
                    Text("After 10 minutes of quiet").tag(10)
                    Text("After 20 minutes of quiet").tag(20)
                    Text("After 30 minutes of quiet").tag(30)
                    Text("Never").tag(0)
                } label: {
                    Text("Ask \u{201C}Still recording?\u{201D}")
                    Text("Recording never stops by itself until 3 hours.")
                }
                Toggle(isOn: $showInMenuBar) {
                    Text("Show Verbatim in the menu bar")
                    Text("While recording it always shows, so you know it's on.")
                }
                Toggle(isOn: $messagesOn) {
                    Text("Tell me things when Verbatim is hidden")
                    Text("Like \u{201C}Still recording?\u{201D} or low battery, as a quiet banner. Never a sound.")
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in refresh() }
        .onChange(of: chosenID) { model.micSettingChanged() }
    }

    private var chosenMic: Mic? { mics.first { $0.id == chosenID } }

    private var micHelp: String {
        if chosenMic?.isBluetooth == true {
            return "AirPods and other Bluetooth mics sound worse than the MacBook mic for a whole classroom."
        }
        if !chosenID.isEmpty, chosenMic == nil {
            return "This mic isn't plugged in, so Verbatim uses the MacBook mic."
        }
        return "USB and wireless mics, like a DJI, show up here when plugged in. If one is unplugged in class, Verbatim switches to the MacBook mic and keeps going. It never switches to AirPods by itself."
    }

    private func refresh() { mics = Microphones.list() }
}

/// Settings > Look (design pass): glass or solid sidebar, soft boxes or
/// paper cards for recordings, transcript text size, and how times show.
struct LookSettings: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SidebarLook.key) private var sidebarLook: SidebarLook = .glass
    @AppStorage(RowLook.key) private var rowLook: RowLook = .soft
    @AppStorage(TextSize.key) private var textSize = TextSize.normal
    @AppStorage(TimeStyle.key) private var timeStyle: TimeStyle = .clock
    @AppStorage(TimeStyle.copyKey) private var timesInCopies = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    LookTile(title: "Glass", selected: sidebarLook == .glass) { sidebarLook = .glass } preview: {
                        SidebarPreview(glass: true)
                    }
                    LookTile(title: "Solid", selected: sidebarLook == .solid) { sidebarLook = .solid } preview: {
                        SidebarPreview(glass: false)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                Text(reduceTransparency
                     ? "Reduce transparency is on in your Mac's Accessibility settings, so the sidebar is always solid."
                     : "Glass lets your desktop show through, blurred. Solid is a plain sheet, easier to read over busy desktop pictures.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                PageHeader(lede: "How Verbatim looks. Nothing here changes what gets recorded.", first: "Sidebar")
            }

            Section("Recordings in the sidebar") {
                HStack(spacing: 16) {
                    LookTile(title: "Soft boxes", selected: rowLook == .soft) { rowLook = .soft } preview: {
                        RowsPreview(look: .soft)
                    }
                    LookTile(title: "Paper cards", selected: rowLook == .cards) { rowLook = .cards } preview: {
                        RowsPreview(look: .cards)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                Text("Soft boxes are quieter. Paper cards stand out more, and the open one turns dark.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Transcript") {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("A").font(.system(size: 11))
                        Slider(value: $textSize, in: TextSize.range, step: 1)
                            .frame(width: 160)
                            .accessibilityLabel("Transcript text size")
                            .accessibilityValue("\(Int(textSize)) points")
                        Text("A").font(.system(size: 17))
                    }
                } label: {
                    Text("Text size")
                    Text("Also \u{2318}+ and \u{2318}\u{2212} anywhere in the app, \u{2318}0 for normal.")
                }
                Text("\(Text("Mr. Yurt:").fontWeight(.semibold)) Kweku Tsin carried the pot up to the sky.")
                    .font(Theme.transcript(textSize))
                    .fixedSize(horizontal: false, vertical: true)
                Picker(selection: $timeStyle) {
                    Text("Clock time (10:42)").tag(TimeStyle.clock)
                    Text("Time since start (37:12)").tag(TimeStyle.sinceStart)
                } label: {
                    Text("Times")
                    Text("Imported files always show time since start.")
                }
                Toggle(isOn: $timesInCopies) {
                    Text("Include times when copying and exporting")
                    Text(timesInCopies ? "Each line starts with its time, like [10:42]." : "Just the words. Cleaner for pasting into Claude.")
                }
            }
        }
    }
}

/// A choice with a little picture of it (Settings > Look).
struct LookTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview()
                    .frame(width: 112, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Color.primary.opacity(0.15),
                                          lineWidth: selected ? 2.5 : 1)
                    }
                Text(title)
                    .font(.callout.weight(selected ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tiny window: desktop colors, a sidebar (glass or solid), paper.
struct SidebarPreview: View {
    let glass: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.71, blue: 0.88),
                                    Color(red: 0.94, green: 0.68, blue: 0.58)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(Theme.ink.opacity(0.16)).frame(height: 6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(width: 40)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(glass ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Theme.sidebarSolid))
                }
                .padding(5)
                Theme.paper
            }
        }
    }
}

/// Three tiny sidebar rows in one style, the middle one open.
struct RowsPreview: View {
    let look: RowLook

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                let open = i == 1
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill(open: open))
                    .shadow(color: .black.opacity(look == .cards ? 0.15 : 0), radius: 0.8, y: 0.5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill((look == .cards && open ? Theme.paper : Theme.ink).opacity(0.4))
                            .frame(width: 44, height: 4)
                            .padding(.leading, 6)
                    }
                    .frame(height: 15)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarSolid)
    }

    private func fill(open: Bool) -> Color {
        switch look {
        case .soft: Theme.ink.opacity(open ? 0.16 : 0.06)
        case .cards: open ? Theme.ink : Theme.card
        }
    }
}

/// Settings > Shortcuts (design pass): its own page, so General stays short.
struct ShortcutSettings: View {
    static let shortcuts: [(String, String)] = [
        ("Do anything", "\u{2318}K"),
        ("New recording", "\u{2318}N"),
        ("Start or stop", "\u{2318}R"),
        ("Pause or resume", "\u{21E7}\u{2318}P"),
        ("Add marker", "\u{2318}D"),
        ("Mini window", "\u{21E7}\u{2318}M"),
        ("Copy all", "\u{21E7}\u{2318}C"),
        ("Copy new since last copy", "\u{2325}\u{2318}C"),
        ("Find in transcript", "\u{2318}F"),
        ("Text bigger, smaller", "\u{2318}+  \u{2318}\u{2212}"),
        ("Transcribe a Voice Memo", "\u{2318}O"),
        ("Show or hide the sidebar", "\u{2303}\u{2318}S"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.shortcuts.indices, id: \.self) { i in
                    LabeledContent(Self.shortcuts[i].0) {
                        Text(Self.shortcuts[i].1)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                PageHeader(lede: "These work anywhere in Verbatim. \u{2318}K finds everything else.")
            }
        }
    }
}

struct UpdateSettings: View {
    @Environment(Updater.self) private var updater
    @AppStorage(Updater.autoKey) private var auto = true
    @AppStorage(Updater.testBuildsKey) private var testBuilds = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(AppInfo.version).textSelection(.enabled)
                }
                Toggle("Check for updates automatically", isOn: $auto)
                Toggle(isOn: $testBuilds) {
                    Text("Include test builds")
                    Text("Test builds have changes Claude is still working on, so you can try them before they're final.")
                }
                LabeledContent {
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.state == .checking)
                } label: {
                    Text("Check for an update")
                    if !statusText.isEmpty { Text(statusText) }
                }
            } header: {
                PageHeader(lede: "Verbatim updates itself from GitHub.")
            }
        }
    }

    private var statusText: String {
        switch updater.state {
        case .checking: return "Checking…"
        case .downloading(let v): return "Downloading \(v)…"
        case .ready(let v): return "\(v) is ready. Restart from the bar at the bottom of the window."
        case .idle:
            if let problem = updater.problem { return problem }
            guard let last = updater.lastChecked else { return "" }
            return "You have the newest version. Last checked \(last.formatted(date: .omitted, time: .shortened))"
        }
    }
}

/// Settings > Claude: lets the Claude desktop app read transcripts by itself
/// (a tool call, not copy and paste). One button; see `ClaudeConnector`.
struct ClaudeSettings: View {
    @State private var state = ClaudeConnector.state()
    @State private var problem: String?
    @State private var copied: String?

    private static let examples = [
        "What did the teacher say about the quiz in my latest Verbatim recording?",
        "Summarise today's English class from Verbatim, with the marked parts first.",
        "Search my Verbatim transcripts for Anansi and tell me which classes talked about him.",
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch state {
                    case .noClaude:
                        Button("Get Claude") { NSWorkspace.shared.open(ClaudeConnector.downloadURL) }
                    case .notConnected:
                        Button("Connect to Claude") { run { try ClaudeConnector.connect() } }
                            .buttonStyle(.borderedProminent)
                    case .moved:
                        Button("Reconnect") { run { try ClaudeConnector.connect() } }
                            .buttonStyle(.borderedProminent)
                    case .connected:
                        Button("Disconnect") { run { try ClaudeConnector.disconnect() } }
                    }
                } label: {
                    Text(title)
                    Text(problem ?? help)
                }
            } header: {
                PageHeader(lede: "Let the Claude app read your transcripts by itself, so you don't copy and paste. You ask Claude a question, Claude asks Verbatim. Nothing leaves this Mac until Claude reads a transcript in a chat.")
            }

            Section("What Claude can do") {
                Label("See the list of your recordings", systemImage: "list.bullet")
                Label("Read a transcript, with speaker names and your markers", systemImage: "text.alignleft")
                Label("Search every transcript for a word", systemImage: "magnifyingglass")
                Label("Read the class being recorded right now", systemImage: "waveform")
                Label {
                    Text("It can't record, change or delete anything")
                    Text("What Claude reads becomes part of your chat with Claude, like text you paste there. Claude asks you before it uses Verbatim the first time.")
                } icon: {
                    Image(systemName: "lock")
                }
            }

            Section("Try asking Claude") {
                ForEach(Self.examples, id: \.self) { example in
                    LabeledContent {
                        Button(copied == example ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(example, forType: .string)
                            copied = example
                        }
                    } label: {
                        Text(example)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear { state = ClaudeConnector.state() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state = ClaudeConnector.state()
        }
    }

    private var title: String {
        switch state {
        case .noClaude: "The Claude app isn't on this Mac"
        case .notConnected: "Not connected"
        case .moved: "Claude can't find Verbatim"
        case .connected: "Connected to Claude"
        }
    }

    private var help: String {
        switch state {
        case .noClaude: "This works with the Claude desktop app (not the website). Get it, open it once, then come back here."
        case .notConnected: "One click. You can disconnect any time."
        case .moved: "Verbatim was moved since you connected. Reconnect to fix it."
        case .connected: "If Claude is open, quit it (\u{2318}Q) and open it again. Then Verbatim shows under Connectors in Claude's chat box."
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        state = ClaudeConnector.state()
    }
}

/// Settings > Voices (step 7c): voices Verbatim remembers. Switch one off or
/// forget it. Nothing to set up: renaming a speaker adds it.
struct VoiceSettings: View {
    private var library: VoiceLibrary { .shared }
    private var names: SpeakerNames { .shared }
    @State private var confirmForget: VoiceLibrary.Voice?
    /// The last name removed from the speaker menu list, for Undo.
    @State private var removedName: (name: String, index: Int, id: UUID)?

    var body: some View {
        let voices = library.voices.sorted { $0.savedAt > $1.savedAt }
        Form {
            Section {
                if voices.isEmpty {
                    Text("No voices yet. Click a speaker's name in a transcript and pick Rename.")
                        .foregroundStyle(.secondary)
                }
                ForEach(voices) { voice in
                    row(voice)
                }
            } header: {
                PageHeader(lede: "When you rename a speaker in a transcript (like Speaker 1 to Mr. Yurt), Verbatim saves 20 seconds of that voice on this Mac. New recordings then know them by name from the first line.",
                           first: "Voices Verbatim knows")
            } footer: {
                if library.voices.filter(\.enabled).count > VoiceLibrary.maxInUse {
                    Text("Only the \(VoiceLibrary.maxInUse) newest switched-on voices are used, so there's room for new people too.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if names.recent.isEmpty {
                    Text("None yet. Names you type for a speaker show up here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(names.recent, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button {
                            guard let i = Speakers.forget(name) else { return }
                            let r = (name: name, index: i, id: UUID())
                            removedName = r
                            Task {
                                try? await Task.sleep(for: .seconds(10))
                                if removedName?.id == r.id { removedName = nil }
                            }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Stop offering \(name)")
                        .accessibilityLabel("Remove \(name)")
                    }
                }
                if let removed = removedName {
                    HStack(spacing: 8) {
                        Text("Removed \(removed.name).").font(.callout)
                        Button("Undo") {
                            Speakers.restore(removed.name, at: removed.index)
                            removedName = nil
                        }
                        .buttonStyle(.link)
                        .fontWeight(.medium)
                        Spacer()
                    }
                }
            } header: {
                Text("Names offered in the speaker menu")
            } footer: {
                Text("The last 8 names you typed for a speaker, offered in every recording. Removing one only stops it being offered. Transcripts keep their names.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Forget \(confirmForget?.name ?? "")'s voice?", isPresented: Binding(
            get: { confirmForget != nil }, set: { if !$0 { confirmForget = nil } }
        )) {
            Button("Forget", role: .destructive) {
                if let v = confirmForget { library.forget(v.id) }
                confirmForget = nil
            }
            Button("Cancel", role: .cancel) { confirmForget = nil }
        } message: {
            Text("The saved sound is deleted. Transcripts keep their names. To get it back, rename the speaker again.")
        }
    }

    private func row(_ voice: VoiceLibrary.Voice) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Toggle("Use", isOn: Binding(get: { voice.enabled }, set: { library.setEnabled(voice.id, $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(voice.enabled ? "Used in new recordings. Switch off to stop without forgetting." : "Not used. Switch on to use it again.")
                    .accessibilityLabel("Use \(voice.name)'s voice")
                Button("Forget…") { confirmForget = voice }
            }
        } label: {
            Text(voice.name)
            Text("From \(voice.from), \(Int(voice.seconds)) s")
        }
    }
}

/// Settings > Words (step 8): names Parakeet listens for, and fixes for what
/// it still gets wrong. Removing has Undo right here.
struct WordSettings: View {
    private var list: WordList { .shared }
    @State private var newWord = ""
    @State private var wordProblem: String?
    @State private var fixFrom = ""
    @State private var fixTo = ""
    @State private var fixProblem: String?
    @State private var undo: Removed?

    private struct Removed: Equatable {
        var text: String
        var inFixes = false
        var id = UUID()
        var run: () -> Void
        static func == (a: Removed, b: Removed) -> Bool { a.id == b.id }
    }

    var body: some View {
        Form {
            Section {
                if list.words.isEmpty {
                    Text("No words yet. Add names that are hard to spell, like people and places from class.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(list.words.enumerated()), id: \.offset) { _, word in
                    removable {
                        Text(word)
                    } remove: {
                        guard let i = list.removeWord(word) else { return }
                        offerUndo("Removed \(word).") { list.insertWord(word, at: i) }
                    }
                }
                HStack {
                    TextField("New word", text: $newWord, prompt: Text("Add a name, like Kweku Tsin"))
                        .labelsHidden()
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .onChange(of: newWord) { wordProblem = nil }
                if let wordProblem { problem(wordProblem) }
                if let undo, !undo.inFixes { undoLine(undo) }
                WordModelNote(inSettings: true)
            } header: {
                PageHeader(lede: "Names and words Verbatim listens for, live and in files. When it hears something close, it writes your spelling. A misheard name can fix itself a few seconds after it shows up.",
                           first: "Word list")
            }

            Section {
                if list.fixes.isEmpty {
                    Text("No fixes yet. When you correct a word in a transcript, Verbatim asks if it should remember it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(list.fixes.enumerated()), id: \.offset) { _, fix in
                    removable {
                        HStack(spacing: 8) {
                            Text(fix.from).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("to")
                            Text(fix.to)
                        }
                    } remove: {
                        guard let i = list.removeFix(fix) else { return }
                        offerUndo("Removed the fix for \(fix.from).", inFixes: true) { list.insertFix(fix, at: i) }
                    }
                }
                HStack {
                    TextField("Heard as", text: $fixFrom, prompt: Text("Heard as"))
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Write", text: $fixTo, prompt: Text("Write"))
                        .labelsHidden()
                        .onSubmit(addFix)
                    Button("Add", action: addFix)
                        .disabled(fixFrom.trimmingCharacters(in: .whitespaces).isEmpty
                                  || fixTo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .onChange(of: fixFrom + "|" + fixTo) { fixProblem = nil }
                if let fixProblem { problem(fixProblem) }
                if let undo, undo.inFixes { undoLine(undo) }
            } header: {
                Text("Fixes")
            } footer: {
                Text("Whenever Verbatim writes the left side, it writes the right side instead. Whole words only, so other words are never broken. Lines you edited are left alone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A row with a remove button on the right.
    private func removable<Label: View>(@ViewBuilder _ label: () -> Label, remove: @escaping () -> Void) -> some View {
        HStack {
            label()
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
            .accessibilityLabel("Remove")
        }
    }

    private func undoLine(_ undo: Removed) -> some View {
        HStack(spacing: 8) {
            Text(undo.text).font(.callout)
            Button("Undo") {
                undo.run()
                self.undo = nil
            }
            .buttonStyle(.link)
            .fontWeight(.medium)
            Spacer()
        }
    }

    private func problem(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func addWord() {
        switch list.addWord(newWord) {
        case .added: newWord = ""
        case .alreadyThere(let w): wordProblem = "\(w) is already in the list."
        case .problem(let p): wordProblem = p
        }
    }

    private func addFix() {
        let fix = PhraseFix(from: WordList.clean(fixFrom), to: WordList.clean(fixTo))
        if let p = WordList.problem(with: fix) {
            fixProblem = p
            return
        }
        if let old = list.addFix(fix) {
            offerUndo("Changed the fix for \(fix.from).", inFixes: true) {
                list.removeFix(PhraseFix(from: fix.from, to: fix.to))
                list.insertFix(old, at: list.fixes.count)
            }
        }
        fixFrom = ""
        fixTo = ""
    }

    private func offerUndo(_ text: String, inFixes: Bool = false, run: @escaping () -> Void) {
        let r = Removed(text: text, inFixes: inFixes, run: run)
        undo = r
        Task {
            try? await Task.sleep(for: .seconds(10))
            if undo == r { undo = nil }
        }
    }
}

/// Settings > Transcription (step 10): the three downloads and where they
/// stand, and naming recordings from what was said.
struct TranscriptionSettings: View {
    @AppStorage(AutoName.enabledKey) private var autoName = true
    private var speakers: SpeakerModel { .shared }

    var body: some View {
        Form {
            Section {
                LiveModelStatusLine()
                statusRow("Speaker labels", note: "Tells Mr. Yurt apart from students.", ready: speakers.isReady, text: speakerText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word list helper").font(.body.weight(.medium))
                    WordModelNote(inSettings: true)
                }
            } header: {
                PageHeader(lede: "Everything runs on this Mac and works offline. These download once. If one breaks, Verbatim downloads it again by itself.",
                           first: "Downloads")
            }

            Section("Names") {
                Toggle(isOn: $autoName) {
                    Text("Name recordings from what was said")
                    Text("After you stop, your Mac's Apple Intelligence reads the transcript and picks a short name, like \u{201C}Anansi and the sky god\u{201D}. On this Mac, offline. Names you type yourself are never changed.")
                }
                if autoName, let reason = AutoName.unavailableReason {
                    Text(reason)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var speakerText: String {
        switch speakers.state {
        case .ready: "Ready."
        case .waiting: "Downloads by itself after the speech model."
        case .downloading(let f): "Downloading, \(Int(f * 100))% of \(SpeakerEngine.sizeText)."
        case .preparing: "Getting ready. First time only."
        case .failed(let f): "Stopped at \(Int(f * 100))%. Trying again by itself."
        }
    }

    private func statusRow(_ title: String, note: String, ready: Bool, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: ready ? "checkmark" : "arrow.down")
                .fontWeight(.semibold)
                .foregroundStyle(ready ? Color.green : Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text("\(note) \(text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
