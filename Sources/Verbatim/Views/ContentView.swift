import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow
    /// Small window = small layout, like Claude (Ryan): below `compactWidth`
    /// the sidebar hides itself so the transcript keeps a readable width.
    /// Wide again, it comes back by itself.
    ///
    /// The window never changes size for the sidebar (Ryan, 2026-11-20: it
    /// used to grow wider each time he opened it, "bigger and bigger").
    /// Window at least `compactWidth`: the sidebar opens inside it and the
    /// transcript gets narrower. Narrower than that: it slides in over the
    /// transcript (`floating`) and slides away on a click outside, Esc, or
    /// picking a recording.
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var hidForSpace = false
    @State private var floating = false
    /// A file is held over the window (C3: nothing showed it could be dropped).
    @State private var fileOver = false
    @State private var width: CGFloat = 1200
    /// 760: the system sidebar button stopped working below about 745 pt
    /// (0.1.109 test), and opening it in a window too narrow made macOS fight
    /// over the layout until it crashed (0.1.98, 0.1.102). So below this the
    /// split view's sidebar column stays shut and the floating one is used.
    static let compactWidth: CGFloat = 760
    private static let roomyWidth: CGFloat = 820
    static let floatingWidth: CGFloat = 270

    private func fitSidebar(to width: CGFloat) {
        self.width = width
        if width < Self.compactWidth, columns != .detailOnly, !hidForSpace {
            hidForSpace = true
            columns = .detailOnly
        } else if width >= Self.roomyWidth, hidForSpace || floating {
            // Room again: the floating sidebar becomes the normal one.
            hidForSpace = false
            floating = false
            columns = .all
        }
    }

    /// Our own sidebar button (the system one is removed). Never resizes the window.
    private func toggleSidebar() {
        if floating {
            floating = false // hid for space stays as it was: wide again, it comes back
        } else if columns == .detailOnly {
            if width < Self.compactWidth {
                floating = true
            } else {
                hidForSpace = false
                // After this layout pass, never in the middle of it (0.1.98 crash).
                Task { @MainActor in columns = .all }
            }
        } else {
            hidForSpace = false
            columns = .detailOnly
        }
    }

    private var sidebarShown: Bool { floating || columns != .detailOnly }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .toolbar(removing: .sidebarToggle)
                // The sidebar keeps at least 230 pt; the main area gives way
                // instead (Ryan saw it squeezed under the window's edge).
                // See the note on the detail column: never let the list's own
                // height decide how tall the window's content is.
                .frame(minHeight: 0, idealHeight: 300, maxHeight: .infinity)
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
                        .help(sidebarShown ? "Hide the sidebar (⌃⌘S)" : "Show the sidebar (⌃⌘S)")
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    model.importAudio(urls)
                    return true
                } isTargeted: { fileOver = $0 }
                .overlay {
                    if fileOver {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                Label("Drop to transcribe", systemImage: "waveform.badge.plus")
                                    .font(.title3.weight(.medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .padding(8)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: fileOver)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.isBusy || model.stoppedNote != nil || model.deletedNote != nil || model.status != nil || updater.isReady {
                        BottomBar()
                    }
                }
                // NavigationSplitView makes itself as tall as this column
                // *wants* to be (title bar + content + bottom bar), not as tall
                // as the window. On Ryan's Mac that was 692 pt in a 552 pt
                // window, so the sidebar's top and bottom were outside it
                // (0.1.115 layout details). Saying "I want little, I take what
                // I'm given" makes the split view follow the window.
                .frame(minWidth: 0, idealWidth: 400, maxWidth: .infinity,
                       minHeight: 0, idealHeight: 300, maxHeight: .infinity)
                // In the main column, not over the whole split view: there
                // the click on the dimmed part went to the split view under
                // it (smoke test, 2026-11-20) and the sidebar didn't close. With
                // the sidebar column shut, this column is the whole window.
                .overlay(alignment: .leading) {
                    FloatingSidebar(shown: floating) { floating = false }
                }
                .animation(.snappy(duration: 0.22), value: floating)
        }
        // Here, not on the sidebar: with the sidebar hidden (narrow window),
        // New Group… from the start page or ⌘K couldn't show it.
        .modifier(GroupNameAlert())
        .overlay {
            if model.showCommandMenu {
                CommandMenuView()
            }
        }
        .animation(.snappy(duration: 0.18), value: model.showCommandMenu)
        // Picking a recording (or Recently Deleted, or starting one) closes it.
        .onChange(of: model.selection) { floating = false }
        .onChange(of: model.sidebarPicks) { floating = false }
        .onChange(of: model.showingDeleted) { floating = false }
        .onAppear {
            MainWindow.open = { openWindow(id: "main") }
            if let w = (Messages.mainWindows.first ?? NSApp.keyWindow)?.frame.width { width = w }
            LaunchTimer.shared.mark("window shown")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // Changed after this layout pass ends, never in the middle of it:
            // showing or hiding the sidebar while the window is laying out can
            // crash (Ryan's crash on 0.1.98).
            Task { @MainActor in fitSidebar(to: width) }
        }
    }
}

/// The sidebar in a window too narrow to fit it beside the transcript: it
/// slides in from the left over the transcript, which is dimmed a little and
/// doesn't move. A click on the dimmed part or Esc slides it away.
private struct FloatingSidebar: View {
    @AppStorage(SidebarLook.key) private var sidebarLook: SidebarLook = .glass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shown: Bool
    let close: () -> Void

    var body: some View {
        // Slides in and out (quick start, gentle stop, so it never feels slow).
        ZStack(alignment: .leading) {
            if shown {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityLabel("Close the sidebar")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { close() } // VoiceOver, and the smoke test's clicks
                    .transition(.opacity)
                SidebarView()
                    .frame(width: ContentView.floatingWidth)
                    .frame(maxHeight: .infinity)
                    .background {
                        Group {
                            if sidebarLook == .solid || reduceTransparency {
                                Theme.sidebarSolid
                            } else {
                                Rectangle().fill(.regularMaterial)
                            }
                        }
                        .ignoresSafeArea()
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Theme.line).frame(width: 1).ignoresSafeArea()
                    }
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.18), radius: 16, x: 4)
                    .background {
                        // Esc slides it away.
                        Button("Close the sidebar", action: close)
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                    .transition(.move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(shown)
    }
}

/// "Name this group", for a new group or Rename Group…, from anywhere
/// (sidebar, start page, ⌘K).
private struct GroupNameAlert: ViewModifier {
    @Environment(RecorderModel.self) private var model
    @State private var draft = ""
    private var store: GroupStore { .shared }

    func body(content: Content) -> some View {
        content
            .alert("Name this group", isPresented: Binding(
                get: { model.renameGroupRequest != nil },
                set: { if !$0, model.renameGroupRequest != nil {
                    // Closed without OK (Esc): same as Cancel.
                    model.renameGroupRequest = nil
                    model.cancelNewGroup()
                } })
            ) {
                TextField("Like English 2026", text: $draft)
                Button("OK") {
                    if let id = model.renameGroupRequest { model.finishGroupName(id, draft) } else { model.keepNewGroup() }
                    model.renameGroupRequest = nil
                }
                Button("Cancel", role: .cancel) {
                    model.renameGroupRequest = nil
                    model.cancelNewGroup()
                }
            } message: {
                Text("One group per class works well. Pick an icon by clicking the one next to its name.")
            }
            .onChange(of: model.renameGroupRequest) {
                if let id = model.renameGroupRequest { draft = store.group(id)?.name ?? "" }
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
            model.lineTool = nil // a tool belongs to the transcript it was picked up on
            model.selectionChanged() // its Undo link goes too
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
