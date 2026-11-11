import AppKit
import SwiftUI

/// A small window that floats on top of every app (step 10, Ryan's ask), top
/// left by default. Shows that it's recording, what was just said, any
/// message, and five buttons. Drag it anywhere; the spot is remembered.
/// Shows on every desktop and over full-screen apps.
@MainActor
@Observable
final class MiniWindow {
    static let shared = MiniWindow()
    private static let frameName = "VerbatimMiniWindow"

    @ObservationIgnored private var panel: NSPanel?
    private(set) var isShown = false

    private init() {}

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        isShown = true
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
    }

    /// Back to the big window: the mini one goes away.
    func expand() {
        hide()
        MainWindow.show()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("mini")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
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
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host

        if !panel.setFrameUsingName(Self.frameName), let screen = NSScreen.main {
            // Top left, just under the menu bar.
            let area = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.minX + 16, y: area.maxY - size.height - 16))
        }
        panel.setFrameAutosaveName(Self.frameName)
        return panel
    }
}

/// What's inside the mini window.
struct MiniView: View {
    @Environment(RecorderModel.self) private var model

    private var paused: Bool { model.phase == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isBusy, let info = model.current {
                HStack(spacing: 8) {
                    Waveform(levels: Array(model.levels.suffix(12)), paused: paused)
                        .frame(height: 22)
                        .scaleEffect(0.8, anchor: .leading)
                        .frame(width: 60, alignment: .leading)
                    Text(RecorderModel.clock(model.elapsed))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(paused ? .secondary : .primary)
                        .contentTransition(.numericText())
                    if paused {
                        Text("Paused").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(info.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                LastLines(id: info.id, count: 2, size: 13.5)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            } else {
                Text("Not recording")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
            }

            MiniMessage()

            Divider()
            HStack(spacing: 2) {
                if model.isBusy {
                    MiniButton("Copy new since last copy", "doc.on.doc") { model.copy(.new, from: model.currentID) }
                    MiniButton("Add marker", "flag") { model.addMarker() }
                        .disabled(model.markerTarget == nil)
                    MiniButton(paused ? "Resume" : "Pause", paused ? "play.fill" : "pause.fill") { model.togglePause() }
                    MiniButton("Stop", "stop.fill") { model.stop() }
                } else {
                    MiniButton("Start recording", "record.circle") { Task { await model.start() } }
                }
                MiniButton("Back to the big window", "arrow.up.left.and.arrow.down.right") { MiniWindow.shared.expand() }
            }
            .padding(4)
        }
        .frame(width: 320)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .animation(.snappy(duration: 0.25), value: model.status?.id)
    }
}

/// The bottom bar's message, in the mini window (with its link).
private struct MiniMessage: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        if let feedback = model.copyFeedback {
            line(Text(feedback.text), link: nil)
        } else if let status = model.status {
            line(Text(status.text), link: status.action)
        } else if let note = model.stoppedNote {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Text(note.text).font(.caption)
                    Spacer(minLength: 0)
                    Button("Undo Stop") { model.undoStop() }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
    }

    private func line(_ text: Text, link: RecorderModel.Status.Action?) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                text.font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let link {
                    Button(BottomBar.linkTitle(link)) { model.perform(link) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One icon button, with its name on hover and for VoiceOver.
private struct MiniButton: View {
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
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(title)
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
