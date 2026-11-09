import AVFoundation
import CoreAudio

/// A microphone as shown in Settings.
struct Mic: Identifiable, Hashable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let isBluetooth: Bool

    /// Friendlier name for the built-in mic, matching the layout ("Using the MacBook mic").
    var displayName: String { isBuiltIn ? "MacBook mic" : name }
}

enum Microphones {
    /// UserDefaults key for the chosen mic. Empty means "MacBook mic" (the default).
    static let chosenKey = "microphoneID"

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func list() -> [Mic] {
        devices().map(mic(for:))
    }

    static func mic(for device: AVCaptureDevice) -> Mic {
        let t = UInt32(bitPattern: device.transportType)
        return Mic(
            id: device.uniqueID,
            name: device.localizedName,
            isBuiltIn: t == kAudioDeviceTransportTypeBuiltIn,
            isBluetooth: t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
        )
    }

    static func builtIn() -> AVCaptureDevice? {
        devices().first { mic(for: $0).isBuiltIn } ?? AVCaptureDevice.default(for: .audio)
    }

    static var chosenID: String {
        UserDefaults.standard.string(forKey: chosenKey) ?? ""
    }

    /// The mic to record with: the one picked in Settings if it is plugged in,
    /// otherwise the MacBook mic. Never picks AirPods on its own.
    static func resolve() -> (device: AVCaptureDevice?, fellBack: Bool) {
        let chosen = chosenID
        if !chosen.isEmpty {
            if let d = devices().first(where: { $0.uniqueID == chosen }) {
                return (d, false)
            }
            return (builtIn(), true)
        }
        return (builtIn(), false)
    }
}
