import Foundation

/// Measures how long the app's main thread (the one that draws everything)
/// takes to answer, ten times a second. Ryan reported lag while recording
/// that nobody could measure, so Help > Copy Layout Details (⌃⌘L) now ends
/// with these numbers, split into "recording" and "not recording".
/// A healthy app answers in a few thousandths of a second.
final class HitchMeter: @unchecked Sendable {
    static let shared = HitchMeter()

    private struct Bucket {
        var checks = 0
        var over100 = 0
        var over500 = 0
        var worst = 0.0
        var total = 0.0

        mutating func add(_ late: Double) {
            checks += 1
            total += late
            worst = max(worst, late)
            if late > 0.1 { over100 += 1 }
            if late > 0.5 { over500 += 1 }
        }

        var text: String {
            guard checks > 0 else { return "no checks yet" }
            return String(format: "%d checks, %d slower than 0.1 s, %d slower than 0.5 s, worst %.2f s, average %.3f s",
                          checks, over100, over500, worst, total / Double(checks))
        }
    }

    private let queue = DispatchQueue(label: "verbatim.hitch", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    // queue only
    private var waiting = false
    private var sentAt: UInt64 = 0
    /// Was it recording when the main thread last answered? A stall is
    /// counted as "while recording" if it began or ended during a recording
    /// (a stall that only ends after Pause used to land in the wrong row).
    private var wasRecording = false
    private var lastSample: UInt64 = 0
    private var samplesTaken = 0
    private var recording = Bucket()
    private var idle = Bucket()

    private init() {}

    func start() {
        queue.async {
            guard self.timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 1, repeating: 0.1)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
    }

    /// One check at a time: while the main thread is stuck, the wait just grows.
    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        if waiting {
            // Stuck for 1.5 s in a recording: photograph what the app is doing.
            if wasRecording, now - sentAt > 1_500_000_000, now - lastSample > 30_000_000_000 || lastSample == 0 {
                takeSample(now)
            }
            return
        }
        waiting = true
        sentAt = now
        let sent = now
        DispatchQueue.main.async {
            let late = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1e9
            let busy = MainActor.assumeIsolated { RecorderModel.shared.phase == .recording }
            self.queue.async {
                if busy || self.wasRecording { self.recording.add(late) } else { self.idle.add(late) }
                self.wasRecording = busy
                self.waiting = false
            }
        }
    }

    private static var sampleFile: URL {
        let folder = RecordingStore.root.deletingLastPathComponent().appending(path: "Diagnostics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "stall.txt")
    }

    /// Runs macOS's own `sample` tool on Verbatim for 3 seconds. It writes
    /// down what every thread is busy with, which is the only way to see
    /// what the main thread is stuck on. Only the newest one is kept.
    private func takeSample(_ now: UInt64) {
        lastSample = now
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "3", "-mayDie", "-file", Self.sampleFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil { samplesTaken += 1 }
    }

    /// The useful parts of the newest sample: what the main thread was in,
    /// and the functions at the top of the list for all threads.
    private func sampleText() -> String {
        guard samplesTaken > 0 else { return "STALL SAMPLE: none taken (no stall over 1.5 s while recording since launch)" }
        guard let text = try? String(contentsOf: Self.sampleFile, encoding: .utf8) else {
            return "STALL SAMPLE: \(samplesTaken) taken, but the file isn't there (yet). Wait 5 seconds and copy again."
        }
        let lines = text.components(separatedBy: "\n")
        var out = ["STALL SAMPLE (\(samplesTaken) taken since launch, newest shown)"]
        if let start = lines.firstIndex(where: { $0.contains("com.apple.main-thread") }) {
            out.append("main thread:")
            for line in lines[(start + 1)...].prefix(170) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("+") else { break }
                out.append("  " + String(trimmed.prefix(150)))
            }
        }
        if let top = lines.firstIndex(where: { $0.hasPrefix("Sort by top of stack") }) {
            out.append("busiest, all threads:")
            for line in lines[(top + 1)...].prefix(30) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append("  " + String(line.trimmingCharacters(in: .whitespaces).prefix(150)))
            }
        }
        return out.joined(separator: "\n")
    }

    /// The numbers since the last report, then starts counting afresh.
    func report() -> String {
        queue.sync {
            let behind = LiveFeed.shared.behind()
            let live = String(format: "LIVE TEXT BEHIND THE MIC (audio waiting for the models): %.1f s now, worst %.1f s since the last copy", behind.now, behind.worst)
            let gap = String(format: "MIC: longest wait between two bits of audio %.2f s since the last copy", LiveFeed.shared.worstGapSeconds())
            let text = "MAIN THREAD (since the last copy)\n  while recording: \(recording.text)\n  not recording: \(idle.text)\n\(live)\n\(gap)\n\(sampleText())"
            recording = Bucket()
            idle = Bucket()
            return text
        }
    }
}
