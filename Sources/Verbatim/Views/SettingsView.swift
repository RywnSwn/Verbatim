import AVFoundation
import SwiftUI

/// Settings > General. Only the microphone for now; the rest arrives in step 10.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @Environment(RecorderModel.self) private var model
    @AppStorage(Microphones.chosenKey) private var chosenID = ""
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
