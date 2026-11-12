import SwiftUI
import UniformTypeIdentifiers

@main
struct VerbatimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = RecorderModel.shared
    @State private var transcriber = Transcriber.shared
    @State private var live = LiveTranscriber.shared
    @State private var updater = Updater.shared
    /// Settings > General: keep the icon in the menu bar when not recording.
    /// While recording it always shows, so you know it's on.
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        WindowGroup("Verbatim", id: "main") {
            ContentView()
                .environment(model)
                .environment(transcriber)
                .environment(live)
                .environment(updater)
                .frame(minWidth: 680, minHeight: 500) // small windows get the compact layout
                .tint(Theme.accent)
                .task { updater.startAutomaticChecks() }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Verbatim") { AboutBox.show() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                Button("Remove Verbatim and Its Data…") { Uninstaller.run() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Recording") { model.showNewRecording() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Transcribe a Recording…") { model.chooseFilesToImport() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .textEditing) {
                Button("Find…") { model.requestFind() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(model.shownID == nil)
                Button("Find Next") { model.nextMatch(1) }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(model.searchText.isEmpty)
                Button("Find Previous") { model.nextMatch(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(model.searchText.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button("Find a Command or Recording…") { model.showCommandMenu.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Make Text Bigger") { TextSize.change(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Make Text Smaller") { TextSize.change(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Normal Text Size") { TextSize.set(TextSize.normal) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button(MiniWindow.shared.isShown ? "Hide Mini Window" : "Show Mini Window") { MiniWindow.shared.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandMenu("Transcript") {
                Group {
                    Button("Copy All") { model.copy(.all) }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button("Copy New Since Last Copy") { model.copy(.new) }
                        .keyboardShortcut("c", modifiers: [.command, .option])
                    Button("Copy Last 10 Minutes") { model.copy(.lastTenMinutes) }
                    Button("Copy Marked Parts Only") { model.copy(.marked) }
                    Divider()
                    Button("Export as Plain Text…") { model.export(.text) }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("Export as Markdown…") { model.export(.markdown) }
                }
                .disabled(!model.hasShownLines)
            }
            CommandGroup(replacing: .help) {
                Button("Copy Layout Details") { LayoutDetails.copy() }
                    .keyboardShortcut("l", modifiers: [.control, .command])
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

                Button("Add Marker") { model.addMarker() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(!model.canMark)

                Divider()

                Button("Play or Pause Audio") {
                    if let id = model.shownID {
                        if Playback.shared.isShowing(id) { Playback.shared.toggle() } else { model.playAudio(id) }
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model.shownID == nil || model.shownID == model.currentID
                    || model.recordings.first { $0.id == model.shownID }?.hasAudio != true)

                Divider()

                Button("Undo Stop") { model.undoStop() }
                    .disabled(model.stoppedNote == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
                .environment(live)
        }

        MenuBarExtra(isInserted: Binding(get: { showInMenuBar || model.isBusy }, set: { showInMenuBar = $0 })) {
            MenuBarPanel()
                .environment(model)
                .environment(live)
                .environment(transcriber)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Messages.shared.setUp()
            // Name anything that stopped before it got a name (step 10).
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                AutoName.shared.considerAll(RecorderModel.shared.recordings)
            }
        }
    }

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

/// About Verbatim: version, who it's for, and what it's built with.
@MainActor
enum AboutBox {
    static func show() {
        let credits = NSMutableAttributedString(
            string: "Made for English class. Records, writes down every word, and keeps it all on this Mac.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        )
        credits.append(NSAttributedString(
            string: "Speech: NVIDIA Parakeet and Sortformer, through FluidAudio. Names: Apple Intelligence, on this Mac.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: AppInfo.version,
        ])
    }
}
