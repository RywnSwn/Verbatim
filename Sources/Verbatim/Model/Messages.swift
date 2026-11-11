import AppKit
import IOKit.ps
import Observation
import UserNotifications

/// Where a message shows up depends on how much of Verbatim you can see
/// (step 10, Ryan's call). The less you can see, the more it stands out,
/// only as much as needed, and never with a sound (he's in class):
/// - Verbatim in front: the bottom bar only (the status spot, as before).
/// - Mini window open: the mini window shows it.
/// - Window behind other apps: a dot on the menu bar icon and a Dock badge;
///   important ones also get a silent banner.
/// - Window closed or minimized: a silent banner for everything worth knowing.
@MainActor
@Observable
final class Messages {
    static let shared = Messages()

    static let enabledKey = "messagesWhenHidden"
    static let stillRecordingCategory = "STILL_RECORDING"
    static let stopAction = "STOP"
    static let keepAction = "KEEP"

    struct Message {
        var id: String
        var title: String
        var body: String
        /// Gets a banner even when the window is just behind other apps.
        var important: Bool
        var stopButton = false
    }

    /// Something happened while you weren't looking. Shows as a dot on the menu
    /// bar icon and a Dock badge, until Verbatim comes to the front.
    private(set) var unseen = 0 {
        didSet { NSApp.dockTile.badgeLabel = unseen > 0 ? String(unseen) : nil }
    }

    @ObservationIgnored private var asked = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Handles the banners' buttons. Kept here so it stays alive.
    @ObservationIgnored private let delegate = BannerDelegate()

    private init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unseen = 0 }
        })
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self?.windowWillClose(window) }
        })
    }

    /// Call once at launch: sets up the Stop button on "Still recording?".
    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let stop = UNNotificationAction(identifier: Self.stopAction, title: "Stop recording", options: [])
        let keep = UNNotificationAction(identifier: Self.keepAction, title: "Keep going", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.stillRecordingCategory, actions: [stop, keep], intentIdentifiers: [], options: []),
        ])
    }

    // MARK: - Where things are

    enum Visibility { case front, mini, behind, hidden }

    static var mainWindows: [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    var visibility: Visibility {
        let mainShown = Self.mainWindows.contains { $0.isVisible && !$0.isMiniaturized }
        if NSApp.isActive, mainShown { return .front }
        if MiniWindow.shared.isShown { return .mini }
        return mainShown ? .behind : .hidden
    }

    // MARK: - Posting

    /// The bottom bar already shows the message; this adds whatever the
    /// situation needs on top.
    func post(_ message: Message, force: Bool = false) {
        let where_ = visibility
        switch where_ {
        case .front, .mini:
            if !force { return }
        case .behind:
            unseen += 1
            if !message.important, !force { return }
        case .hidden:
            unseen += 1
        }
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        banner(message)
    }

    /// A silent banner. Asks for permission the first time one is needed.
    private func banner(_ message: Message) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = nil // never a sound: it's class
        content.interruptionLevel = .active
        if message.stopButton { content.categoryIdentifier = Self.stillRecordingCategory }
        let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil)
        let needsAsk = !asked
        asked = true
        Task {
            if needsAsk { _ = try? await center.requestAuthorization(options: [.alert, .badge]) }
            try? await center.add(request)
        }
    }

    /// Takes a banner away once it's no longer true (you spoke again, plugged in).
    func withdraw(_ id: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: - The messages

    static func stillRecording(minutes: Int, elapsed: TimeInterval) -> Message {
        Message(id: "stillRecording", title: "Still recording?",
                body: "Quiet for \(minutes) minutes. Class might be over. \(RecorderModel.minutesText(elapsed)) recorded.",
                important: true, stopButton: true)
    }

    static func battery(_ percent: Int) -> Message {
        Message(id: "battery", title: "Battery at \(percent)%",
                body: "Plug in so the recording doesn't stop when the Mac goes to sleep.", important: true)
    }

    static func problem(_ text: String) -> Message {
        Message(id: "problem", title: "Verbatim needs you", body: text, important: true)
    }

    static func stoppedAtLimit(_ title: String) -> Message {
        Message(id: "limit", title: "Recording stopped at 3 hours",
                body: "\(title) is saved. That's the longest a recording can be.", important: false)
    }

    static func memoDone(_ title: String, lines: Int) -> Message {
        Message(id: "memo-\(title)", title: "Voice Memo is ready",
                body: lines == 1 ? "\(title) has 1 line." : "\(title) has \(lines) lines.", important: false)
    }

    // MARK: - Closed the window while recording

    /// The first time only: says where Verbatim went.
    private func windowWillClose(_ window: NSWindow?) {
        guard let window, window.identifier?.rawValue.hasPrefix("main") == true,
              RecorderModel.shared.isBusy else { return }
        let key = "toldAboutMenuBar"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        banner(Message(id: "menuBar", title: "Still recording",
                       body: "Verbatim keeps going in the menu bar, at the top right of your screen.", important: true))
    }
}

/// The notification banners' buttons and clicks.
final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Messages.stopAction:
                RecorderModel.shared.stop()
            case Messages.keepAction:
                break
            default:
                MainWindow.show()
            }
        }
    }
}

/// The Mac's battery, for the 15% warning.
enum Battery {
    /// Percent left and whether it's running on battery. nil on a Mac with no battery.
    static func read() -> (percent: Int, onBattery: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let state = d[kIOPSPowerSourceStateKey] as? String
            return (current * 100 / max, state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}

/// Bringing the big window back from the menu bar, mini window or a banner.
@MainActor
enum MainWindow {
    /// Set by a SwiftUI view that has `openWindow`, so AppKit code can open it.
    static var open: (() -> Void)?

    static func show() {
        NSApp.activate()
        if let window = Messages.mainWindows.first {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            open?()
        }
    }
}
