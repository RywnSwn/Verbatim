import AppKit
import SwiftUI

/// A small window that floats on top of every app (step 10, Ryan's ask), top
/// left by default. Redesigned 2026-11-12 to match docs/design/MiniWindow.html:
/// no title bar (so no empty strip on top), a close button, the last lines
/// (click one to fix it), named buttons, and a real "ready" look when idle.
/// Drag it anywhere; the spot is remembered. Shows on every desktop and over
/// full-screen apps.
@MainActor
@Observable
final class MiniWindow {
    static let shared = MiniWindow()
    /// Where the top left corner was, so it opens there again. Only the spot
    /// is kept, never the size: the old "VerbatimMiniWindow" autosave put
    /// back the size of the pre-redesign window, AppKit and SwiftUI then
    /// fought over the height until the app crashed (0.1.150, Ryan opened the
    /// mini window while not recording).
    private static let spotKey = "MiniWindowTopLeft"

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var keyObserver: NSObjectProtocol?
    @ObservationIgnored private var moveObserver: NSObjectProtocol?
    private(set) var isShown = false
    /// Goes up when typing in the mini window has to end (it was closed, or
    /// you clicked into another window): the line being edited saves itself.
    private(set) var endEditing = 0

    private init() {}

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        isShown = true
    }

    /// Only hides the window. Recording never stops because of this.
    func hide() {
        endEditing += 1
        panel?.orderOut(nil)
        isShown = false
    }

    /// Back to the big window: the mini one goes away.
    func expand() {
        hide()
        MainWindow.show()
    }

    /// Typing needs the keyboard. The panel takes it without bringing
    /// Verbatim's other windows in front of the app you're in.
    func takeKeyboard() { panel?.makeKey() }

    /// The window takes the height its content wants. Done after the layout
    /// pass, never inside it, and only when the height really changed, so a
    /// resize can never start another resize. The top edge stays put.
    func contentResized(_ size: CGSize) {
        Task { @MainActor in
            guard let panel = self.panel else { return }
            let height = ceil(size.height)
            guard height > 20, abs(panel.frame.height - height) > 0.5 || abs(panel.frame.width - MiniView.width) > 0.5 else { return }
            var frame = panel.frame
            frame.origin.y = frame.maxY - height
            frame.size = CGSize(width: MiniView.width, height: height)
            panel.setFrame(frame, display: true, animate: false)
            panel.invalidateShadow()
        }
    }

    private func makePanel() -> NSPanel {
        // No title bar at all: a hidden one still kept its height free at the
        // top (the "weird margin" Ryan saw). Corners and edge are drawn by MiniView.
        let panel = MiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: MiniView.width, height: 160),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("mini")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let root = MiniView()
            .environment(RecorderModel.shared)
            .environment(LiveTranscriber.shared)
            .environment(Transcriber.shared)
            .tint(Theme.accent)
        // No automatic sizing: contentResized(_:) sets the size itself.
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: MiniView.width, height: 160))

        // Forget the old saved frame (it held the wrong size).
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame VerbatimMiniWindow")
        let size = panel.frame.size
        if let saved = UserDefaults.standard.string(forKey: Self.spotKey),
           case let topLeft = NSPointFromString(saved),
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(topLeft) }) {
            panel.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - size.height))
        } else if let screen = NSScreen.main {
            // Top left, just under the menu bar.
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.minX + 16, y: area.maxY - size.height - 16))
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { note in
            guard let frame = (note.object as? NSWindow)?.frame else { return }
            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: "MiniWindowTopLeft")
        }

        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { _ in
            Task { @MainActor in MiniWindow.shared.endEditing += 1 }
        }
        return panel
    }
}

/// A panel with no title bar can't take the keyboard unless it says so.
private final class MiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// What's inside the mini window.
struct MiniView: View {
    static let width: CGFloat = 330
    @Environment(RecorderModel.self) private var model

    private var paused: Bool { model.phase == .paused }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            topRow
            if model.isBusy, let id = model.currentID {
                MiniLines(id: id)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            } else {
                MiniIdle()
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
            }

            MiniMessage()

            if model.isBusy {
                Divider()
                HStack(spacing: 2) {
                    MiniButton("Copy new", "doc.on.doc", help: "Copy new since last copy") {
                        model.copy(.new, from: model.currentID)
                    }
                    MiniButton("Marker", "flag", help: "Mark this moment") { model.addMarker() }
                        .disabled(model.markerTarget == nil)
                    MiniButton(paused ? "Resume" : "Pause", paused ? "play.fill" : "pause.fill",
                               help: paused ? "Resume recording" : "Pause recording") { model.togglePause() }
                    MiniButton("Stop", "stop.fill", help: "Stop and save") { model.stop() }
                }
                .padding(4)
            }
        }
        .frame(width: Self.width)
        // Always its own natural height, whatever the window offers, so the
        // height never depends on the window's size (no back and forth).
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.ink.opacity(0.18), lineWidth: 0.5) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { MiniWindow.shared.contentResized($0) }
        .animation(.snappy(duration: 0.25), value: model.status?.id)
        // Until the window has caught up, sit at the top of it.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Close, then what's going on, then back to the big window.
    private var topRow: some View {
        HStack(spacing: 8) {
            MiniIconButton("xmark", help: model.isBusy ? "Close the mini window. Recording keeps going." : "Close the mini window") {
                MiniWindow.shared.hide()
            }
            if model.isBusy {
                MiniClock(paused: paused)
                if paused {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Theme.ink.opacity(0.08), in: Capsule())
                }
                Spacer(minLength: 4)
                Text(model.current?.title ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Verbatim")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 4)
            }
            MiniIconButton("arrow.up.left.and.arrow.down.right", help: "Back to the big window") {
                MiniWindow.shared.expand()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 6)
    }
}

/// The moving bars and the timer. Its own view, so the clock (20 ticks a
/// second) redraws only this, not the whole mini window.
private struct MiniClock: View {
    @Environment(RecorderModel.self) private var model
    let paused: Bool

    var body: some View {
        Waveform(levels: Array(model.levels.suffix(12)), paused: paused)
            .frame(height: 22)
            .scaleEffect(0.8, anchor: .leading)
            .frame(width: 60, alignment: .leading)
        Text(RecorderModel.clock(model.elapsed))
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(paused ? .secondary : .primary)
    }
}

/// The last lines of the class being recorded. Click one to fix it right
/// here: Enter saves, Esc cancels, clicking away saves. While you type, that
/// line stays on top and is never changed; new words start a new line under
/// it (same rule as the big window). At most two newer lines show, then a count.
private struct MiniLines: View {
    @Environment(RecorderModel.self) private var model
    @Environment(LiveTranscriber.self) private var live
    let id: UUID

    @State private var editing: EditKey?
    @State private var draft = LineDraft()
    @FocusState private var focused: Bool

    private struct EditKey: Equatable {
        var source: LineSource
        var start: Double
    }

    private static let shown = 3
    private static let font = Font.system(size: 13.5, design: .serif)

    var body: some View {
        let all = model.shownLines(id)
        let editIndex = editing.flatMap { key in
            all.firstIndex { $0.source == key.source && $0.line.start == key.start }
        }
        let from = editIndex ?? max(0, all.count - Self.shown)
        let rows = Array(all[from..<min(all.count, from + Self.shown)])
        let more = editIndex == nil ? 0 : all.count - (from + rows.count)
        let labels = Speakers.labeler(id)

        VStack(alignment: .leading, spacing: 2) {
            if all.isEmpty {
                Text(live.volatile.isEmpty ? "Words show up here a couple of seconds after they're said." : live.volatile)
                    .font(Self.font)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            ForEach(Array(rows.enumerated()), id: \.element.line.start) { i, row in
                if editIndex != nil, i == 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        LineEditor(draft: draft, focused: $focused, font: Self.font,
                                   onSave: { save() }, onCancel: { finish() })
                        Text("Enter saves. Esc cancels. New words go on a new line.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                } else {
                    MiniLineRow(text: row.line.text, name: labels.name(row.line), font: Self.font,
                                newest: i == rows.count - 1) { begin(row.line, row.source) }
                }
            }
            if more > 0 {
                Text(more == 1 ? "1 more new line below. Save to see it." : "\(more) more new lines below. Save to see them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: focused) {
            // Clicking somewhere else in the mini window saves.
            if !focused, editing != nil { save() }
        }
        .onChange(of: MiniWindow.shared.endEditing) { if editing != nil { save() } }
        .onChange(of: editIndex == nil) {
            // The line went away (deleted in the big window): stop editing.
            if editing != nil, editIndex == nil { finish() }
        }
        .onDisappear { if editing != nil { save() } }
    }

    private func begin(_ line: Transcript.Line, _ source: LineSource) {
        if editing != nil { save() }
        draft.text = line.text
        editing = EditKey(source: source, start: line.start)
        if source == .live { live.editing = (id, line.start) }
        MiniWindow.shared.takeKeyboard()
        Task { @MainActor in focused = true }
    }

    private func save() {
        guard let key = editing else { return }
        finish()
        model.editLine(id, key.source, start: key.start, text: draft.text)
    }

    private func finish() {
        editing = nil
        focused = false
        live.editing = nil
    }
}

/// One line you can click to fix. Lighter when it's an older line.
private struct MiniLineRow: View {
    let text: String
    let name: String?
    let font: Font
    let newest: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TranscriptList.labelled(Text(text), name)
                .font(font)
                .foregroundStyle(newest ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.secondary))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.ink.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.horizontalText)
        .help("Click to fix this line")
        .accessibilityHint("Edit line")
    }
}

/// Not recording: says it's ready, which mic and group, a real Start button,
/// and the last recording with Copy all. Mic access off: says so, with the fix.
private struct MiniIdle: View {
    @Environment(RecorderModel.self) private var model

    private var blocked: Bool { model.micPermission == .denied || model.micPermission == .restricted }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(blocked ? "Verbatim can't hear anything" : "Ready to record")
                    .font(.system(size: 17, design: .serif))
                Text(blocked ? "Microphone access is off for Verbatim. Turn it on, then come back." : readyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if blocked {
                Button { model.openMicSettings() } label: {
                    Label("Open Microphone settings", systemImage: "gearshape")
                }
                .buttonStyle(MiniMainButtonStyle())
            } else {
                Button { Task { await model.start() } } label: {
                    Label("Start recording", systemImage: "record.circle")
                }
                .buttonStyle(MiniMainButtonStyle())
            }
            if let last = model.recordings.first {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(last.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("\(RecorderModel.minutesText(last.duration)), last recording")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    MiniLink("Copy all", "doc.on.doc") { model.copy(.all, from: last.id) }
                }
            }
        }
    }

    /// "MacBook mic. Saves into English 2026."
    private var readyNote: String {
        let groups = GroupStore.shared
        let group = groups.group(groups.lastUsedID)?.name ?? "Recents"
        return "\(model.micName). Saves into \(group)."
    }
}

/// The one filled button in the mini window (Start recording).
private struct MiniMainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// The bottom bar's message, in the mini window (with its link).
private struct MiniMessage: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        if let feedback = model.copyFeedback {
            line(feedback.text) { EmptyView() }
        } else if let status = model.status {
            line(status.text) {
                if let action = status.action {
                    MiniLink(BottomBar.linkTitle(action), Self.icon(action)) { model.perform(action) }
                }
            }
        } else if let note = model.stoppedNote {
            line(note.text) {
                MiniLink("Undo Stop", "arrow.uturn.backward") { model.undoStop() }
            }
        }
    }

    private func line<Link: View>(_ text: String, @ViewBuilder link: () -> Link) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                link()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private static func icon(_ action: RecorderModel.Status.Action) -> String {
        switch action {
        case .stopRecording: "stop.fill"
        case .resume: "play.fill"
        case .undoDelete, .undoLine, .undoAudioDelete: "arrow.uturn.backward"
        case .showFile: "folder"
        case .changeVoice: "person.2"
        }
    }
}

/// A text link with a small icon in front (Undo, Undo Stop, Copy all).
private struct MiniLink: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, _ icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .underline(hovering)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .fixedSize()
    }
}

/// A small icon-only button in the top row (close, back to the big window).
private struct MiniIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    init(_ icon: String, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(Theme.ink.opacity(hovering ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One bottom button: an icon with its name under it.
private struct MiniButton: View {
    let title: String
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, _ icon: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 15)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Theme.ink.opacity(hovering && isEnabled ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The last few lines of a recording, with speaker names, in the transcript serif.
/// The older line is lighter.
struct LastLines: View {
    @Environment(RecorderModel.self) private var model
    @Environment(LiveTranscriber.self) private var live
    let id: UUID
    var count = 2
    var size: Double = 13.5

    var body: some View {
        let lines = Array(model.shownLines(id).map(\.line).suffix(count))
        let labels = Speakers.labeler(id)
        VStack(alignment: .leading, spacing: 4) {
            if lines.isEmpty {
                Text(live.volatile.isEmpty ? "Words show up here a couple of seconds after they're said." : live.volatile)
                    .font(.system(size: size, design: .serif))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Group {
                    if let name = labels.name(line) {
                        Text("\(Text(name + ":").font(.system(size: size - 1, weight: .semibold))) \(line.text)")
                    } else {
                        Text(line.text)
                    }
                }
                .font(.system(size: size, design: .serif))
                .foregroundStyle(i == lines.count - 1 ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.secondary))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
