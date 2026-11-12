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

    /// The useful parts of the newest sample: the whole main thread, then for
    /// every thread that is inside Verbatim, FluidAudio or CoreML the deepest
    /// frames (what it is waiting in), then the busiest functions overall.
    private func sampleText() -> String {
        guard let text = try? String(contentsOf: Self.sampleFile, encoding: .utf8) else {
            return samplesTaken == 0
                ? "STALL SAMPLE: none taken (no stall over 1.5 s while recording)"
                : "STALL SAMPLE: \(samplesTaken) taken, but the file isn't there (yet). Wait 10 seconds and copy again."
        }
        let made = (try? FileManager.default.attributesOfItem(atPath: Self.sampleFile.path)[.modificationDate] as? Date) ?? nil
        let when = made.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "?"
        let lines = text.components(separatedBy: "\n")
        var out = ["STALL SAMPLE (written \(when); \(samplesTaken) taken since launch)"]

        // Threads in the call graph: a header line ("  2468 Thread_123  DispatchQueue_1: ..."), then its frames.
        let graphStart = (lines.firstIndex { $0.hasPrefix("Call graph:") } ?? -1) + 1
        let graphEnd = lines.firstIndex { $0.hasPrefix("Total number in stack") || $0.hasPrefix("Sort by top of stack") } ?? lines.count
        var threads: [(header: String, frames: [String])] = []
        if graphStart > 0, graphStart < graphEnd {
            for line in lines[graphStart..<graphEnd] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if trimmed.first?.isNumber == true, trimmed.contains("Thread_") {
                    threads.append((trimmed, []))
                } else if !threads.isEmpty {
                    threads[threads.count - 1].frames.append(Self.clean(trimmed))
                }
            }
        }
        if threads.isEmpty { out.append("(no threads found in the file; send the file itself: \(Self.sampleFile.path))") }
        for (i, thread) in threads.enumerated() {
            if i == 0 {
                out.append("FIRST THREAD (main): \(thread.header.prefix(120))")
                out += thread.frames.prefix(260).map { "  " + $0 }
            } else if thread.frames.contains(where: { $0.contains("Verbatim") || $0.contains("FluidAudio") || $0.contains("CoreML") || $0.contains("Espresso") }) {
                out.append("THREAD: \(thread.header.prefix(120))")
                out += thread.frames.suffix(14).map { "  " + $0 }
            }
            if out.count > 520 { break }
        }
        out.append("other threads: \(threads.count)")
        if let top = lines.firstIndex(where: { $0.hasPrefix("Sort by top of stack") }) {
            out.append("busiest, all threads:")
            for line in lines[(top + 1)...].prefix(12) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append("  " + String(line.trimmingCharacters(in: .whitespaces).prefix(110)))
            }
        }
        return out.joined(separator: "\n")
    }

    /// "+   ! 2468 foo(bar)  (in Verbatim) + 123  [0x1023]" becomes "2468 foo(bar) (in Verbatim)".
    private static func clean(_ frame: String) -> String {
        var text = Substring(frame).drop { "+!:| ".contains($0) }
        if let address = text.range(of: "  [0x") { text = text[..<address.lowerBound] }
        var out = String(text)
        if let offset = out.range(of: #"\) \+ \d+$"#, options: .regularExpression) {
            out = String(out[..<offset.lowerBound]) + ")"
        }
        return String(out.replacingOccurrences(of: "  ", with: " ").prefix(150))
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
