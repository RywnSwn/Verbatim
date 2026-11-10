import AVFoundation
import SwiftUI

/// Settings > General: speaker names, microphone and times. The rest arrives in step 10.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
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
    @AppStorage(Speakers.teacherKey) private var teacherName = ""
    @AppStorage(Speakers.studentKey) private var studentName = ""
    @State private var mics: [Mic] = []

    var body: some View {
        Form {
            TextField("Teacher:", text: $teacherName, prompt: Text(Speakers.teacherDefault))
                .frame(maxWidth: 220)
            TextField("Students show as:", text: $studentName, prompt: Text(Speakers.studentDefault))
                .frame(maxWidth: 220)
            Text("The voice that talks the most gets the teacher's name. Click a name in a transcript to fix it. Changing these changes every recording.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 6)

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
