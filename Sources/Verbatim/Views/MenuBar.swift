import AppKit
import SwiftUI

/// The menu bar icon (step 10): a tiny waveform, plus the timer while
/// recording. Reads `menuBars` and `menuClock` (2 changes a second at most),
/// never `levels` or `elapsed`: see the note on them in RecorderModel. A dot means a message you haven't seen yet.
struct MenuBarLabel: View {
    @Environment(RecorderModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(
                levels: model.isBusy ? model.menuBars : nil,
                paused: model.phase == .paused,
                dot: Messages.shared.unseen > 0
            ))
            if model.isBusy {
                Text(model.menuClock)
                    .monospacedDigit()
            }
        }
        .onAppear { MainWindow.open = { openWindow(id: "main") } }
        .accessibilityLabel(model.isBusy ? (model.phase == .paused ? "Verbatim, paused" : "Verbatim, recording") : "Verbatim")
    }
}

/// Draws the waveform as a template image, so it follows the menu bar's color.
enum MenuBarIcon {
    /// Shape of the icon when nothing is recording.
    private static let resting: [CGFloat] = [0.3, 0.65, 1, 0.65, 0.3]

    static func image(levels: [Float]?, paused: Bool, dot: Bool) -> NSImage {
        let size = NSSize(width: dot ? 20 : 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let barWidth: CGFloat = 2, gap: CGFloat = 1.3, maxHeight: CGFloat = 12
            for i in 0..<5 {
                let x = 1 + CGFloat(i) * (barWidth + gap)
                if paused {
                    NSBezierPath(ovalIn: NSRect(x: x, y: 7, width: 2, height: 2)).fill()
                    continue
                }
                let level: CGFloat
                if let levels, i < levels.count {
                    level = levels[i] < 0.15 ? 0 : CGFloat(min(levels[i], 1))
                } else {
                    level = levels == nil ? resting[i] : 0
                }
                let h = max(2, level * maxHeight)
                let rect = NSRect(x: x, y: (16 - h) / 2, width: barWidth, height: h)
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            if dot {
                NSBezierPath(ovalIn: NSRect(x: 15.5, y: 10.5, width: 4.5, height: 4.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// "37:12", or "1:02:05" after an hour.
    static func shortClock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// What opens from the menu bar icon: where things stand, the last two lines,
/// four big buttons for what you press most, and the rest as words.
struct MenuBarPanel: View {
    @Environment(RecorderModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    private var groups: GroupStore { .shared }
    private var mini: MiniWindow { .shared }

    private var paused: Bool { model.phase == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)

            if model.isBusy, let id = model.currentID {
                LastLines(id: id, count: 2, size: 13.5)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            bigButtons
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

            message

            Divider().padding(.horizontal, 10)
            VStack(spacing: 0) {
                if model.isBusy {
                    MenuRow("Copy all", shortcut: "⇧⌘C") { model.copy(.all, from: model.currentID) }
                    MenuRow("Copy last 10 minutes") { model.copy(.lastTenMinutes, from: model.currentID) }
                } else {
                    ForEach(groups.groups) { group in
                        MenuRow("Record in \(group.name)", icon: group.icon, color: group.color) {
                            close()
                            Task { await model.start(in: group.id) }
                        }
                    }
                    MenuRow("Transcribe a Voice Memo…", shortcut: "⌘O") {
                        close()
                        MainWindow.show()
                        model.chooseFilesToImport()
                    }
                    if let last = model.recordings.first {
                        MenuRow("Copy all from \(last.title)") { model.copy(.all, from: last.id) }
                    }
                }
                MenuRow(mini.isShown ? "Hide mini window" : "Show mini window", shortcut: "⇧⌘M") { mini.toggle() }
                Divider().padding(.vertical, 4)
                MenuRow("Open Verbatim") {
                    close()
                    MainWindow.show()
                }
                MenuRow("Settings…", shortcut: "⌘,") {
                    close()
                    NSApp.activate()
                    openSettings()
                }
                if !model.isBusy {
                    MenuRow("Quit Verbatim", shortcut: "⌘Q") { NSApp.terminate(nil) }
                }
            }
            .padding(6)
        }
        .frame(width: 310)
        .animation(.snappy(duration: 0.25), value: model.status?.id)
        .animation(.snappy(duration: 0.25), value: model.copyFeedback?.id)
    }

    @ViewBuilder private var header: some View {
        if model.isBusy, let info = model.current {
            HStack {
                Text(groups.group(info.groupID).map { "\($0.name), \(paused ? "paused" : "recording")" }
                     ?? (paused ? "Paused" : "Recording"))
                Spacer()
                Text(RecorderModel.clock(model.elapsed))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: Int(model.elapsed))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text("Not recording")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var bigButtons: some View {
        HStack(spacing: 6) {
            if model.isBusy {
                BigButton("Copy new", "doc.on.doc") { model.copy(.new, from: model.currentID) }
                BigButton("Marker", "flag") { model.addMarker() }
                    .disabled(model.markerTarget == nil || paused)
                BigButton(paused ? "Resume" : "Pause", paused ? "play.fill" : "pause.fill") { model.togglePause() }
                BigButton("Stop", "stop.fill") { model.stop() }
            } else {
                BigButton("Record", "record.circle") {
                    close()
                    Task { await model.start() }
                }
                BigButton("Voice Memo", "waveform.badge.plus") {
                    close()
                    MainWindow.show()
                    model.chooseFilesToImport()
                }
                BigButton(mini.isShown ? "Hide mini" : "Mini", "pip") { mini.toggle() }
                BigButton("Open", "macwindow") {
                    close()
                    MainWindow.show()
                }
            }
        }
    }

    /// Copy feedback, or the bottom bar's message, with its link.
    @ViewBuilder private var message: some View {
        if let feedback = model.copyFeedback {
            Text(feedback.text)
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.opacity)
        } else if let status = model.status {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(status.text).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let action = status.action {
                    Button(BottomBar.linkTitle(action)) { model.perform(action) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    /// Closes the menu bar window (it's the key window while open).
    private func close() {
        NSApp.keyWindow?.close()
    }
}

/// A big icon button with a word under it, like Control Center.
private struct BigButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, _ icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary.opacity(hovering && isEnabled ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

/// A plain menu line that highlights on hover, like a real menu.
private struct MenuRow: View {
    let title: String
    var shortcut: String?
    var icon: String?
    var color: IconColor = .ink
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, shortcut: String? = nil, icon: String? = nil, color: IconColor = .ink, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(hovering ? .white : color.color)
                        .frame(width: 16)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut).foregroundStyle(hovering ? .white.opacity(0.85) : .secondary)
                }
            }
            .font(.callout)
            .foregroundStyle(hovering ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovering ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
