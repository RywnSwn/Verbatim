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
        guard !waiting else { return }
        waiting = true
        let sent = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async {
            let late = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1e9
            let busy = MainActor.assumeIsolated { RecorderModel.shared.phase == .recording }
            self.queue.async {
                if busy { self.recording.add(late) } else { self.idle.add(late) }
                self.waiting = false
            }
        }
    }

    /// The numbers since the last report, then starts counting afresh.
    func report() -> String {
        queue.sync {
            let text = "MAIN THREAD (since the last copy)\n  while recording: \(recording.text)\n  not recording: \(idle.text)"
            recording = Bucket()
            idle = Bucket()
            return text
        }
    }
}
