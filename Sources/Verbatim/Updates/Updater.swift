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
    /// While downloading: how much is here and how big it is, in bytes
    /// (total 0 = not known yet). B10: there was no progress at all.
    private(set) var downloaded: (done: Int64, total: Int64)?

    /// "42% (17 of 40 MB)", or "" before the size is known.
    var progressText: String {
        guard let d = downloaded, d.total > 0 else { return "" }
        let mb = { (b: Int64) in Int((Double(b) / 1_000_000).rounded()) }
        return "\(Int(Double(d.done) / Double(d.total) * 100))% (\(mb(d.done)) of \(mb(d.total)) MB)"
    }

    var isWorking: Bool {
        switch state {
        case .checking, .downloading: return true
        case .idle, .ready: return false
        }
    }

    /// A failure with a message Ryan can act on.
    private struct Problem: Error {
        let text: String
    }

    @ObservationIgnored private var staged: URL?
    /// Build number of `staged`; a newer one replaces it.
    @ObservationIgnored private var stagedBuild = 0
    /// A check is running (the state stays .ready while it looks for a newer one).
    @ObservationIgnored private var looking = false
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
        // Clean up the downloaded copy of the version now running, and any
        // half download of a version that isn't newer anymore.
        try? FileManager.default.removeItem(at: Self.updatesFolder.appending(path: String(Self.currentBuild)))
        Self.removePartials { $0 <= Self.currentBuild }
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
                // After a failure (no internet, a broken download) try again
                // in 30 minutes, not 4 hours (B10).
                try? await Task.sleep(for: problem == nil ? Self.checkEvery : .seconds(30 * 60))
            }
        }
    }

    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading: return
        case .ready, .idle: break
        }
        // B10: a downloaded update stays ready while it looks for a newer one
        // (it used to stop looking until a restart).
        guard !looking else { return }
        looking = true
        let waiting = state
        if case .idle = state { state = .checking }
        defer {
            lastChecked = Date()
            looking = false
        }

        do {
            guard let release = try await newestRelease(), release.build > stagedBuild else {
                if case .ready(let v) = waiting {
                    state = waiting
                    if userInitiated { RecorderModel.shared.show("Version \(v) is downloaded and ready to install.") }
                } else {
                    state = .idle
                    if userInitiated { RecorderModel.shared.show("You have the newest version (\(Self.currentVersion)).") }
                }
                problem = nil
                UserDefaults.standard.removeObject(forKey: Self.failingSinceKey)
                return
            }
            state = .downloading(version: release.version)
            if userInitiated { RecorderModel.shared.show("Downloading version \(release.version)…") }
            let older = staged
            staged = try await download(release)
            stagedBuild = release.build
            // The older download isn't needed anymore.
            if let older { try? FileManager.default.removeItem(at: older.deletingLastPathComponent()) }
            problem = nil
            UserDefaults.standard.removeObject(forKey: Self.failingSinceKey)
            state = .ready(version: release.version)
        } catch {
            // The update already downloaded is still good.
            if case .ready = waiting, staged != nil { state = waiting } else { state = .idle }
            let text = (error as? Problem)?.text
                ?? "Couldn't reach GitHub. Check the internet and try again."
            problem = text
            // B1: a check that ran by itself (offline in class, every 4 hours)
            // took over the bottom bar for the whole class. Now it's in
            // Settings > Updates, and only says so out loud after 3 days of
            // failing, when not recording, so updates still never fail silently.
            let defaults = UserDefaults.standard
            let since = defaults.object(forKey: Self.failingSinceKey) as? Date ?? Date()
            defaults.set(since, forKey: Self.failingSinceKey)
            let longTime = Date().timeIntervalSince(since) > 3 * 24 * 3600
            if userInitiated || (longTime && !RecorderModel.shared.isBusy) {
                RecorderModel.shared.show("Update didn't work: \(text)")
            }
        }
    }

    /// When automatic checks started failing (cleared by one that works).
    private static let failingSinceKey = "updateFailingSince"

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

    /// What a stopped download had so far (URLSession's resume data), so the
    /// next try picks up from there instead of starting over (B10).
    private static func partialURL(_ build: Int) -> URL {
        updatesFolder.appending(path: "\(build).partial")
    }

    private static func removePartials(where unwanted: (Int) -> Bool) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: updatesFolder.path)) ?? []
        for name in names where name.hasSuffix(".partial") {
            if let build = Int(name.dropLast(".partial".count)), unwanted(build) {
                try? FileManager.default.removeItem(at: updatesFolder.appending(path: name))
            }
        }
    }

    /// Gets the zip into `zip`, with progress. If it stops halfway, what it
    /// had is kept for next time.
    private func fetch(_ url: URL, to zip: URL, build: Int) async throws {
        let partial = Self.partialURL(build)
        var resume = try? Data(contentsOf: partial)
        try? FileManager.default.removeItem(at: partial)
        // Half downloads of other versions aren't needed anymore.
        Self.removePartials { $0 != build }
        downloaded = (0, 0)
        defer { downloaded = nil }
        while true {
            let job = ZipDownload(to: zip) { done, total in
                Task { @MainActor in
                    let me = Updater.shared
                    if me.downloaded != nil { me.downloaded = (done, total) }
                }
            }
            do {
                try await job.run(from: url, resume: resume)
                return
            } catch let stopped as ZipDownload.Stopped {
                if let data = stopped.resume {
                    try? data.write(to: partial, options: .atomic)
                    let sofar = progressText.isEmpty ? "" : " at \(progressText.prefix { $0 != " " })"
                    let when = UserDefaults.standard.bool(forKey: Self.autoKey) ? "in 30 minutes, or press Check Now" : "when you press Check Now"
                    throw Problem(text: "The download stopped\(sofar). It carries on from there \(when).")
                }
                // What was kept couldn't be used (the file on GitHub changed):
                // start over once, from the beginning.
                if resume != nil {
                    resume = nil
                    downloaded = (0, 0)
                    continue
                }
                throw stopped.error
            } catch let refused as ZipDownload.Refused {
                throw Problem(text: "GitHub answered with error \(refused.code) for the download. Try again later.")
            }
        }
    }

    /// Downloads and unzips into Updates/<build>/, then checks it's really Verbatim.
    private func download(_ release: Release) async throws -> URL {
        guard let zipURL = release.zip else { throw URLError(.fileDoesNotExist) }
        let folder = Self.updatesFolder.appending(path: String(release.build), directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let zip = folder.appending(path: "Verbatim.zip")
        try await fetch(zipURL, to: zip, build: release.build)

        let app = folder.appending(path: "Verbatim.app")
        let ok = await Task.detached {
            Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path]) == 0 && Self.isGenuine(app)
        }.value
        try? FileManager.default.removeItem(at: zip)
        guard ok else {
            try? FileManager.default.removeItem(at: folder)
            throw Problem(text: "The download didn't pass the safety check (signature), so it wasn't installed. The version you have still works.")
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

/// One update download with progress. If the internet drops (or the Mac
/// sleeps), it hands back what it had so the next try carries on (B10: it
/// used to start over from nothing, with no progress shown).
private final class ZipDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Stopped halfway. `resume` is what URLSession needs to carry on, if it gave any.
    struct Stopped: Error {
        let resume: Data?
        let error: Error
    }

    /// GitHub said no (404, 500…).
    struct Refused: Error {
        let code: Int
    }

    private let destination: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private let queue: OperationQueue
    // Only touched on `queue` (one at a time).
    private var continuation: CheckedContinuation<Void, Error>?
    private var finishError: Error?
    private var finished = false
    private var lastPercent = -1

    init(to destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    func run(from url: URL, resume: Data?) async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 6 * 3600
        // The session holds on to its delegate until it's invalidated.
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.addOperation {
                self.continuation = c
                let task = resume.map { session.downloadTask(withResumeData: $0) }
                    ?? session.downloadTask(with: url)
                task.resume()
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = max(totalBytesExpectedToWrite, 0)
        // Tell the window once per whole percent, not for every piece.
        let percent = total > 0 ? Int(totalBytesWritten * 100 / total) : -1
        guard percent != lastPercent else { return }
        lastPercent = percent
        progress(totalBytesWritten, total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        progress(fileOffset, max(expectedTotalBytes, 0))
    }

    /// The file is deleted as soon as this returns, so it's moved right here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard code == 200 else {
            finishError = Refused(code: code)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finished = true
        } catch {
            finishError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let error {
            let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            c.resume(throwing: Stopped(resume: resume, error: error))
        } else if let finishError {
            c.resume(throwing: finishError)
        } else if finished {
            c.resume()
        } else {
            c.resume(throwing: URLError(.cannotWriteToFile))
        }
    }
}
