import SwiftUI

@main
struct VerbatimApp: App {
    var body: some Scene {
        WindowGroup("Verbatim") {
            ContentView()
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 1200, height: 780)
    }
}
