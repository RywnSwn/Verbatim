import SwiftUI
import UniformTypeIdentifiers

@main
struct VerbatimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = RecorderModel.shared
    @State private var transcriber = Transcriber.shared
    @State private var updater = Updater.shared

    var body: some Scene {
        WindowGroup("Verbatim", id: "main") {
            ContentView()
                .environment(model)
                .environment(transcriber)
                .environment(updater)
                .frame(minWidth: 820, minHeight: 540)
                .task { updater.startAutomaticChecks() }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                Button("Remove Verbatim and Its Data…") { Uninstaller.run() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Transcribe a Recording…") { model.chooseFilesToImport() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Recording") {
                Button(model.isBusy ? "Stop Recording" : "Start Recording") {
                    model.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(model.phase == .paused ? "Resume" : "Pause") {
                    model.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.isBusy)

                Divider()

                Button("Undo Stop") { model.undoStop() }
                    .disabled(model.stoppedNote == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quitting while recording is the one place a confirm popup is worth it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let model = RecorderModel.shared
            guard model.isBusy else { return .terminateNow }

            let alert = NSAlert()
            alert.messageText = "Recording in progress"
            alert.informativeText = "Stop and save the recording, or keep recording?"
            alert.addButton(withTitle: "Keep Recording")
            alert.addButton(withTitle: "Stop and Quit")
            if alert.runModal() == .alertSecondButtonReturn {
                model.stop()
                return .terminateNow
            }
            return .terminateCancel
        }
    }

    /// Logout or restart: save without asking.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            if RecorderModel.shared.isBusy { RecorderModel.shared.stop() }
        }
    }
}
