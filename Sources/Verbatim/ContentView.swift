import SwiftUI

/// Skeleton window that matches the approved "first launch / empty" layout
/// (docs/design/Empty.dc.html). Recording, mic status and the model
/// download arrive in later milestones.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text("Your recordings will show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            EmptyStateView()
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 0) {
                Text("Hear it once.")
                    .font(.system(size: 54, weight: .medium, design: .serif))
                Text("Keep every word.")
                    .font(.system(size: 54, weight: .regular, design: .serif))
                    .italic()
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button {
                } label: {
                    Text("Start recording")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(true)

                Text("Recording arrives in the next update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(width: 460)

            Text(AppInfo.versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum AppInfo {
    /// For example "Version 0.1.7 (build 7)", so Ryan can tell which build he has.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (build \(build))"
    }
}
