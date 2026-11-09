import SwiftUI

@main
struct VerbatimApp: App {
    var body: some Scene {
        WindowGroup("Verbatim") {
            ContentView()
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            // Only one window for now. Recording-related menu items arrive in step 2.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text("Your recordings will show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            StartView()
        }
    }
}
