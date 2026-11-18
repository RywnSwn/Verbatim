import Darwin
import Foundation

/// How long launch took, in seconds after the app process started: when the
/// saved recordings were read, when the window showed, and when the texts
/// were checked in the background. Shown in ⌃⌘L (Copy Layout Details) and
/// written to the log, so the smoke test can compare builds.
final class LaunchTimer: @unchecked Sendable {
    static let shared = LaunchTimer()

    private let lock = NSLock()
    private let started: Date
    private var marks: [(String, Double)] = []

    private init() {
        started = Self.processStart() ?? Date()
    }

    /// When this process started, from the kernel (so it counts the time
    /// before any of our code runs too).
    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }

    /// Something finished ("window shown"). Only the first time each.
    func mark(_ what: String, detail: String = "") {
        let seconds = Date().timeIntervalSince(started)
        let added: Bool = lock.withLock {
            guard !marks.contains(where: { $0.0 == what }) else { return false }
            marks.append((what, seconds))
            return true
        }
        guard added else { return }
        let line = String(format: "LAUNCH: %@ %.3f s%@\n", what, seconds, detail.isEmpty ? "" : " (\(detail))")
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// "recordings read 0.21 s, window shown 0.48 s" for ⌃⌘L.
    func text() -> String {
        lock.withLock {
            guard !marks.isEmpty else { return "nothing yet" }
            return marks.map { String(format: "%@ %.2f s", $0.0, $0.1) }.joined(separator: ", ")
        }
    }
}
