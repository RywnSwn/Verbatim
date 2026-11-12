import SwiftUI

struct ContentView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            DetailView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let notice = model.recoveryNotice {
                        NoticeLine(text: notice) { model.recoveryNotice = nil }
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
    }
}

/// Picks what the main area shows.
struct DetailView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        // GeometryReader: the main area takes the space the window gives it and
        // never asks for more. Without it, a screen that wants to be taller
        // than the window stretches the whole window content, and the top
        // and bottom of the sidebar end up outside the window.
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
