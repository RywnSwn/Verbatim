import AVFoundation
import SwiftUI

/// Settings: General (microphone and times), Words (step 8), Voices (step 7c), Updates.
/// The rest arrives in step 10.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Words", systemImage: "character.book.closed") {
                WordSettings()
            }
            Tab("Voices", systemImage: "person.wave.2") {
                VoiceSettings()
            }
            Tab("Updates", systemImage: "arrow.down.circle") {
                UpdateSettings()
            }
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @Environment(RecorderModel.self) private var model
    @AppStorage(Microphones.chosenKey) private var chosenID = ""
    @AppStorage(TimeStyle.key) private var timeStyle: TimeStyle = .clock
    @AppStorage(TimeStyle.copyKey) private var timesInCopies = false
    @State private var mics: [Mic] = []

    var body: some View {
        Form {

            Picker("Microphone:", selection: $chosenID) {
                Text("MacBook mic (recommended)").tag("")
                ForEach(mics.filter { !$0.isBuiltIn }) { mic in
                    Text(mic.displayName).tag(mic.id)
                }
                if !chosenID.isEmpty, !mics.contains(where: { $0.id == chosenID }) {
                    Text("Unplugged mic").tag(chosenID)
                }
            }
            Group {
                if chosenMic?.isBluetooth == true {
                    Text("AirPods and other Bluetooth mics sound worse than the MacBook mic for a whole classroom.")
                } else if !chosenID.isEmpty, chosenMic == nil {
                    Text("This mic isn't plugged in, so Verbatim uses the MacBook mic.")
                } else {
                    Text("Verbatim never switches to AirPods by itself.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 6)

            Picker("Times:", selection: $timeStyle) {
                Text("Clock time (10:42)").tag(TimeStyle.clock)
                Text("Time since start (37:12)").tag(TimeStyle.sinceStart)
            }
            .pickerStyle(.radioGroup)
            Text("Imported files always show time since start.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Include times when copying and exporting", isOn: $timesInCopies)
            Text(timesInCopies ? "Each line starts with its time, like [10:42]." : "Just the words. Cleaner for pasting into Claude.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.columns)
        .padding(24)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in refresh() }
        .onChange(of: chosenID) { model.micSettingChanged() }
    }

    private var chosenMic: Mic? { mics.first { $0.id == chosenID } }

    private func refresh() { mics = Microphones.list() }
}

struct UpdateSettings: View {
    @Environment(Updater.self) private var updater
    @AppStorage(Updater.autoKey) private var auto = true
    @AppStorage(Updater.testBuildsKey) private var testBuilds = true

    var body: some View {
        Form {
            LabeledContent("Version:") {
                Text(AppInfo.version).textSelection(.enabled)
            }
            Toggle("Check for updates automatically", isOn: $auto)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Include test builds", isOn: $testBuilds)
                Text("Test builds have changes Claude is still working on, so you can try them before they're final.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("") {
                HStack(spacing: 10) {
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.state == .checking)
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.columns)
        .padding(24)
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

/// Settings > Voices (step 7c): voices Verbatim remembers. Switch one off or
/// forget it. Nothing to set up: renaming a speaker adds it.
struct VoiceSettings: View {
    private var library: VoiceLibrary { .shared }
    @State private var confirmForget: VoiceLibrary.Voice?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("When you rename a speaker in a transcript (like Speaker 1 to Mr. Yurt), Verbatim saves 20 seconds of that voice on this Mac. New recordings then know them by name from the first line.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if library.voices.isEmpty {
                Text("No voices yet. Click a speaker's name in a transcript and pick Rename.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(library.voices.sorted { $0.savedAt > $1.savedAt }) { voice in
                        row(voice)
                        if voice.id != library.voices.sorted(by: { $0.savedAt > $1.savedAt }).last?.id { Divider() }
                    }
                }
                .background(Theme.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                if library.voices.filter(\.enabled).count > VoiceLibrary.maxInUse {
                    Text("Only the \(VoiceLibrary.maxInUse) newest switched-on voices are used, so there's room for new people too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
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
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { voice.enabled }, set: { library.setEnabled(voice.id, $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name).font(.body.weight(.medium))
                    Text("From \(voice.from), \(Int(voice.seconds)) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .help(voice.enabled ? "Used in new recordings. Untick to stop without forgetting." : "Not used. Tick to use it again.")
            Spacer()
            Button("Forget…") { confirmForget = voice }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        var id = UUID()
        var run: () -> Void
        static func == (a: Removed, b: Removed) -> Bool { a.id == b.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Word list").font(.headline)
            Text("Names and words Verbatim listens for, live and in files. When it hears something close, it writes your spelling. A misheard name can fix itself a few seconds after it shows up.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if list.words.isEmpty {
                Text("No words yet. Add names that are hard to spell, like people and places from class.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                rows(list.words, id: \.self) { word in
                    Text(word)
                } remove: { word in
                    guard let i = list.removeWord(word) else { return }
                    offerUndo("Removed \(word).") { list.insertWord(word, at: i) }
                }
            }
            HStack {
                TextField("Add a name, like Kweku Tsin", text: $newWord)
                    .onSubmit(addWord)
                Button("Add", action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onChange(of: newWord) { wordProblem = nil }
            if let wordProblem { problem(wordProblem) }
            WordModelNote(inSettings: true)

            Divider().padding(.vertical, 8)

            Text("Fixes").font(.headline)
            Text("Whenever Verbatim writes the left side, it writes the right side instead. Whole words only, so other words are never broken. Lines you edited are left alone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if list.fixes.isEmpty {
                Text("No fixes yet. When you correct a word in a transcript, Verbatim asks if it should remember it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                rows(list.fixes, id: \.id) { fix in
                    HStack(spacing: 8) {
                        Text(fix.from).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("to")
                        Text(fix.to)
                    }
                } remove: { fix in
                    guard let i = list.removeFix(fix) else { return }
                    offerUndo("Removed the fix for \(fix.from).") { list.insertFix(fix, at: i) }
                }
            }
            HStack {
                TextField("Heard as", text: $fixFrom)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Write", text: $fixTo)
                    .onSubmit(addFix)
                Button("Add", action: addFix)
                    .disabled(fixFrom.trimmingCharacters(in: .whitespaces).isEmpty
                              || fixTo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onChange(of: fixFrom + "|" + fixTo) { fixProblem = nil }
            if let fixProblem { problem(fixProblem) }

            HStack(spacing: 8) {
                if let undo {
                    Text(undo.text).font(.callout)
                    Button("Undo") {
                        undo.run()
                        self.undo = nil
                    }
                    .buttonStyle(.link)
                    .fontWeight(.medium)
                }
            }
            .frame(height: 20)
        }
        .padding(24)
    }

    /// A plain list in a light tint, like Settings > Voices. Scrolls when long.
    private func rows<Item, ID: Hashable, Label: View>(
        _ items: [Item], id: KeyPath<Item, ID>,
        @ViewBuilder label: @escaping (Item) -> Label,
        remove: @escaping (Item) -> Void
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack {
                        label(item)
                        Spacer()
                        Button {
                            remove(item)
                        } label: {
                            Image(systemName: "minus.circle")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove")
                        .accessibilityLabel("Remove")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    if i < items.count - 1 { Divider() }
                }
            }
        }
        .frame(maxHeight: 130)
        .fixedSize(horizontal: false, vertical: items.count <= 4)
        .background(Theme.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func problem(_ text: String) -> some View {
        Text(text)
            .font(.caption)
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
            offerUndo("Changed the fix for \(fix.from).") {
                list.removeFix(PhraseFix(from: fix.from, to: fix.to))
                list.insertFix(old, at: list.fixes.count)
            }
        }
        fixFrom = ""
        fixTo = ""
    }

    private func offerUndo(_ text: String, run: @escaping () -> Void) {
        let r = Removed(text: text, run: run)
        undo = r
        Task {
            try? await Task.sleep(for: .seconds(10))
            if undo == r { undo = nil }
        }
    }
}
