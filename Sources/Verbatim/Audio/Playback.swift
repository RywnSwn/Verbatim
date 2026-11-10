import AVFoundation
import Observation

/// Plays a recording's audio inside the app (Ryan's ask: "Play audio" used to
/// hand the file to Apple Music). One recording at a time. The player bar sits
/// under that recording's transcript, and the line being heard is marked.
@MainActor
@Observable
final class Playback {
    static let shared = Playback()
    static let speeds: [Float] = [1, 1.25, 1.5, 2]
    private static let speedKey = "playbackSpeed"
    static let skipSeconds: Double = 15

    /// The recording whose player bar is showing.
    private(set) var id: UUID?
    private(set) var isPlaying = false
    /// Seconds into the audio.
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    var speed: Float = Playback.savedSpeed {
        didSet {
            player?.rate = speed
            UserDefaults.standard.set(speed, forKey: Self.speedKey)
        }
    }

    /// True while the slider is being dragged, so the clock doesn't fight it.
    @ObservationIgnored var scrubbing = false
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Where each recording was left, so opening it again carries on there.
    @ObservationIgnored private var leftAt: [UUID: Double] = [:]

    private static var savedSpeed: Float {
        let s = UserDefaults.standard.float(forKey: speedKey)
        return speeds.contains(s) ? s : 1
    }

    private init() {}

    func isShowing(_ id: UUID) -> Bool { self.id == id }

    /// Opens the recording's audio and plays it, from `start` if given,
    /// else from where it was left. Returns a reason if it can't.
    @discardableResult
    func play(_ id: UUID, from start: Double? = nil) -> String? {
        if self.id != id || player == nil {
            close()
            let url = RecordingStore.audioURL(id)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "The audio for this recording isn't there any more."
            }
            let p: AVAudioPlayer
            do {
                p = try AVAudioPlayer(contentsOf: url)
            } catch {
                return "Couldn't play the audio: \(error.localizedDescription)"
            }
            p.enableRate = true
            p.rate = speed
            p.prepareToPlay()
            player = p
            self.id = id
            duration = p.duration
            let resume = leftAt[id] ?? 0
            p.currentTime = resume < p.duration - 1 ? resume : 0
            time = p.currentTime
        }
        guard let p = player else { return nil }
        if let start { p.currentTime = max(0, min(start, p.duration)) }
        // Finished: play again from the start.
        if p.duration - p.currentTime < 0.2 { p.currentTime = 0 }
        p.play()
        isPlaying = true
        time = p.currentTime
        startTicker()
        return nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
        if let id, let p = player { leftAt[id] = p.currentTime }
    }

    func toggle() {
        guard let id else { return }
        if isPlaying { pause() } else { play(id) }
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        p.currentTime = max(0, min(seconds, p.duration))
        time = p.currentTime
        if let id { leftAt[id] = time }
    }

    func skip(_ seconds: Double) { seek(to: time + seconds) }

    /// Hides the player bar. Remembers the spot for next time.
    func close() {
        if let id, let p = player { leftAt[id] = p.currentTime }
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        id = nil
        isPlaying = false
        time = 0
        duration = 0
    }

    /// The audio file is going away (recording or audio deleted).
    func forget(_ id: UUID) {
        if self.id == id { close() }
        leftAt[id] = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let p = self.player else { return }
                if !self.scrubbing { self.time = p.currentTime }
                if !p.isPlaying {
                    // Reached the end by itself.
                    if self.isPlaying {
                        self.isPlaying = false
                        self.time = p.duration
                        if let id = self.id { self.leftAt[id] = 0 }
                    }
                    return
                }
            }
        }
    }

    /// 3:07 or 1:02:07.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func speedLabel(_ s: Float) -> String {
        s == Float(Int(s)) ? "\(Int(s))×" : "\(String(format: "%g", Double(s)))×"
    }
}
