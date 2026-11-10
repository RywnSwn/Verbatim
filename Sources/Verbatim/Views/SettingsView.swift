import AVFoundation
import SwiftUI

/// Settings: General (microphone and times), Voices (step 7c), Updates.
/// The rest arrives in step 10.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
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
