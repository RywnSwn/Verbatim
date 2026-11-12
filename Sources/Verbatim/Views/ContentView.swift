import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow
    /// Small window = small layout, like Claude (Ryan): below `compactWidth`
    /// the sidebar hides itself so the main area gets the room. The toolbar
    /// button (or ⌃⌘S) still opens it. Wide again, it comes back by itself.
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var hidForSpace = false
    private static let compactWidth: CGFloat = 860
    private static let roomyWidth: CGFloat = 940

    private func fitSidebar(to width: CGFloat) {
        if width < Self.compactWidth, columns != .detailOnly, !hidForSpace {
            hidForSpace = true
            columns = .detailOnly
        } else if width >= Self.roomyWidth, hidForSpace {
            hidForSpace = false
            columns = .all
        }
    }

    /// Our own sidebar button (the system one is removed). Opening the sidebar
    /// in a window too narrow for it made macOS fight over the layout until
    /// the app crashed (0.1.98, 0.1.102), or do nothing at all. So a narrow
    /// window first grows to make room, then the sidebar opens.
    private func toggleSidebar() {
        if columns == .detailOnly {
            hidForSpace = false
            if let window = Messages.mainWindows.first ?? NSApp.keyWindow,
               window.frame.width < Self.compactWidth {
                var frame = window.frame
                frame.size.width = Self.compactWidth + 20
                if let screen = window.screen?.visibleFrame {
                    frame.size.width = min(frame.size.width, screen.width)
                    if frame.maxX > screen.maxX { frame.origin.x = max(screen.minX, screen.maxX - frame.width) }
                }
                window.setFrame(frame, display: true, animate: true)
                guard frame.width >= Self.compactWidth else { return } // tiny screen: no room at all
            }
            // After the resize has been laid out, never in the middle of it.
            Task { @MainActor in columns = .all }
        } else {
            hidForSpace = false
            columns = .detailOnly
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .toolbar(removing: .sidebarToggle)
                // The sidebar keeps at least 230 pt; the main area gives way
                // instead (Ryan saw it squeezed under the window's edge).
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            DetailView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let notice = model.recoveryNotice {
                        NoticeLine(text: notice) { model.recoveryNotice = nil }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: toggleSidebar) {
                            Label("Sidebar", systemImage: "sidebar.left")
                        }
                        .keyboardShortcut("s", modifiers: [.control, .command])
                        .help(columns == .detailOnly ? "Show the sidebar (⌃⌘S)" : "Hide the sidebar (⌃⌘S)")
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    model.importAudio(urls)
                    return true
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.isBusy || model.stoppedNote != nil || model.deletedNote != nil || model.status != nil || updater.isReady {
                        BottomBar()
                    }
                }
        }
        .overlay {
            if model.showCommandMenu {
                CommandMenuView()
            }
        }
        .animation(.snappy(duration: 0.18), value: model.showCommandMenu)
        .onAppear { MainWindow.open = { openWindow(id: "main") } }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // Changed after this layout pass ends, never in the middle of it:
            // showing or hiding the sidebar while the window is laying out can
            // crash (Ryan's crash on 0.1.98).
            Task { @MainActor in fitSidebar(to: width) }
        }
    }
}

/// Picks what the main area shows.
struct DetailView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        // GeometryReader: the main area takes the space the window gives it and
        // never asks for more. A screen that wants to be taller than the
        // window would otherwise stretch the whole window content and push
        // the top and bottom of the sidebar outside the window.
        GeometryReader { _ in
          Group {
            if model.showingDeleted {
                RecentlyDeletedView()
            } else if let id = model.selection, let info = model.recordings.first(where: { $0.id == id }) {
                if info.id == model.currentID {
                    RecordingNowView(info: info)
                } else {
                    PastRecordingView(info: info)
                }
            } else if model.micPermission == .denied || model.micPermission == .restricted {
                MicBlockedView()
            } else {
                StartView()
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.selection) {
            model.searchText = ""
            // Audio belongs to the transcript on screen; don't keep playing behind another one.
            if Playback.shared.id != model.selection { Playback.shared.close() }
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
    }
}

/// A plain line at the top of the main area (crash recovery). No box, just a divider.
struct NoticeLine: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(text)
                    .font(.callout)
                Button("Got it", action: dismiss)
                    .buttonStyle(.link)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            Divider()
        }
        .background(Theme.paper)
    }
}
