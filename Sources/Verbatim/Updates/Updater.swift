import AppKit
import Observation

/// Checks GitHub Releases for a newer build, downloads it in the background,
/// checks its signature, and swaps it in when Ryan clicks Restart to update.
/// Never restarts while recording.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case downloading(version: String)
        case ready(version: String)
    }

    static let autoKey = "checkForUpdates"
    static let testBuildsKey = "includeTestBuilds"
    private static let releasesURL = URL(string: "https://api.github.com/repos/RywnSwn/Verbatim/releases?per_page=30")!
    private static let checkEvery: Duration = .seconds(4 * 3600)

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?
    /// What went wrong last time, in plain words. nil = last check worked.
    private(set) var problem: String?

    /// A failure with a message Ryan can act on.
    private struct Problem: Error {
        let text: String
    }

    @ObservationIgnored private var staged: URL?
    @ObservationIgnored private var loop: Task<Void, Never>?

    private init() {
        UserDefaults.standard.register(defaults: [Self.autoKey: true, Self.testBuildsKey: true])
    }

    static var currentVersion: String { AppInfo.version }
    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// Why updating can't work from where the app is, if anything.
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var installProblem: String? {
        let path = Bundle.main.bundleURL.path
        if path.contains("/AppTranslocation/") || !FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path) {
            return "Move Verbatim into your Applications folder to get updates."
        }
        return nil
    }

    /// After an update, say so once, so Ryan knows it worked.
    private func announceIfUpdated() {
        let key = "lastLaunchedBuild"
        let last = UserDefaults.standard.integer(forKey: key)
        if last > 0, Self.currentBuild > last {
            RecorderModel.shared.show("Updated to version \(Self.currentVersion).")
        }
        UserDefaults.standard.set(Self.currentBuild, forKey: key)
        // Clean up the downloaded copy of the version now running.
        try? FileManager.default.removeItem(at: Self.updatesFolder.appending(path: String(Self.currentBuild)))
    }

    func startAutomaticChecks() {
        guard loop == nil else { return }
        announceIfUpdated()
        loop = Task {
            try? await Task.sleep(for: .seconds(5)) // let the app finish opening first
            while !Task.isCancelled {
                if UserDefaults.standard.bool(forKey: Self.autoKey) {
                    await check(userInitiated: false)
                }
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
    }

    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading: return
        case .ready(let v):
            if userInitiated { RecorderModel.shared.show("Version \(v) is downloaded and ready to install.") }
            return
        case .idle: break
        }
        state = .checking
        defer { lastChecked = Date() }

        do {
            guard let release = try await newestRelease() else {
                state = .idle
                problem = nil
                if userInitiated { RecorderModel.shared.show("You have the newest version (\(Self.currentVersion)).") }
                return
            }
            state = .downloading(version: release.version)
            if userInitiated { RecorderModel.shared.show("Downloading version \(release.version)…") }
            staged = try await download(release)
            problem = nil
            state = .ready(version: release.version)
        } catch {
            state = .idle
            let text = (error as? Problem)?.text
                ?? "Couldn't reach GitHub. Check the internet and try again."
            problem = text
            // Say it even when the check ran by itself, so updates never fail silently.
            RecorderModel.shared.show("Update didn't work: \(text)")
        }
    }

    func installAndRestart() {
        guard case .ready = state, let newApp = staged, !RecorderModel.shared.isBusy, installProblem == nil else { return }
        let oldApp = Bundle.main.bundleURL
        let script = Self.updatesFolder.appending(path: "install.sh")
        do {
            try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), oldApp.path, newApp.path]
            try p.run()
        } catch {
            RecorderModel.shared.show("Couldn't install the update: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: - Steps

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let prerelease: Bool
        let draft: Bool
        let assets: [Asset]

        /// Tags look like v0.1.25; the last number is the build number.
        var build: Int { Int(tag_name.split(separator: ".").last ?? "") ?? 0 }
        var version: String { String(tag_name.dropFirst()) }
        var zip: URL? { assets.first { $0.name == "Verbatim.zip" }?.browser_download_url }
    }

    private func newestRelease() async throws -> Release? {
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Verbatim-updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 || code == 429 {
            throw Problem(text: "GitHub says too many checks from this internet connection. Try again in an hour.")
        }
        guard code == 200 else { throw Problem(text: "GitHub answered with error \(code). Try again later.") }
        let includeTest = UserDefaults.standard.bool(forKey: Self.testBuildsKey)
        return try JSONDecoder().decode([Release].self, from: data)
            .filter { !$0.draft && $0.zip != nil && (includeTest || !$0.prerelease) }
            .filter { $0.build > Self.currentBuild }
            .max { $0.build < $1.build }
    }

    private static var updatesFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Verbatim/Updates", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Downloads and unzips into Updates/<build>/, then checks it's really Verbatim.
    private func download(_ release: Release) async throws -> URL {
        guard let zipURL = release.zip else { throw URLError(.fileDoesNotExist) }
        let folder = Self.updatesFolder.appending(path: String(release.build), directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let (tempZip, _) = try await URLSession.shared.download(from: zipURL)
        let zip = folder.appending(path: "Verbatim.zip")
        try FileManager.default.moveItem(at: tempZip, to: zip)

        let app = folder.appending(path: "Verbatim.app")
        let ok = await Task.detached {
            Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path]) == 0 && Self.isGenuine(app)
        }.value
        try? FileManager.default.removeItem(at: zip)
        guard ok else {
            try? FileManager.default.removeItem(at: folder)
            throw Problem(text: "The download didn't pass the safety check (signature), so it wasn't installed. Tell Claude.")
        }
        return app
    }

    /// The new app must be signed the same way as this one (same certificate).
    /// While builds are still ad-hoc signed, only the app's identity can be checked.
    nonisolated private static func isGenuine(_ app: URL) -> Bool {
        let own = output("/usr/bin/codesign", ["-d", "-r-", Bundle.main.bundleURL.path])
        var requirement = "identifier \"com.rywnswn.verbatim\""
        if let line = own.split(separator: "\n").first(where: { $0.hasPrefix("designated => ") }),
           !line.contains("cdhash") {
            requirement = String(line.dropFirst("designated => ".count))
        }
        return run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(requirement)", app.path]) == 0
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    nonisolated private static func output(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Waits for Verbatim to quit, swaps the app (keeping the old one if
    /// anything fails), and opens the new one.
    private static let installScript = """
    #!/bin/bash
    PID="$1"; OLD="$2"; NEW="$3"
    for i in $(seq 1 300); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
    BACKUP="${OLD%.app}.previous.app"
    rm -rf "$BACKUP"
    if mv "$OLD" "$BACKUP" && mv "$NEW" "$OLD"; then
      rm -rf "$BACKUP"
    elif [ -d "$BACKUP" ] && [ ! -d "$OLD" ]; then
      mv "$BACKUP" "$OLD"
    fi
    xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
    open "$OLD"
    """
}
