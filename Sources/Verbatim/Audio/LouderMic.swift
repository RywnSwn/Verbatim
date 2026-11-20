import AVFoundation

/// A mic with 2 or more channels (a 2-mic receiver in split mode: one mic
/// left, one right) becomes one channel by following the louder mic: the
/// one someone is talking into gets most of the weight, with a smooth fade
/// when it changes. Averaging both (Nov 19 to 20) halved the teacher's voice
/// and added the far mic's late copy of it plus room noise: Parakeet then
/// wrote run-on text with no capitals or commas (punctuation test, PLAN.md).
/// A mic with one channel never comes here.
/// sampleQueue only (AudioPipeline).
final class LouderMic {
    let format: AVAudioFormat
    private let channels: Int
    /// 10 ms of audio per weighing step.
    private let block: Int
    /// How loud each mic has been lately (mean square, smoothed).
    private var level: [Double]
    /// The weight each mic has right now (adds up to 1).
    private var gain: [Double]

    init?(rate: Double, channels: Int) {
        guard channels >= 2,
              let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return nil }
        format = f
        self.channels = channels
        block = max(16, Int(rate / 100))
        level = Array(repeating: 0, count: channels)
        gain = Array(repeating: 1 / Double(channels), count: channels)
    }

    /// `input`: Float32, not interleaved, `channels` channels, same rate.
    func mix(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = Int(input.frameLength)
        guard let src = input.floatChannelData, Int(input.format.channelCount) == channels,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let dst = out.floatChannelData?[0] else { return nil }
        out.frameLength = AVAudioFrameCount(frames)
        var start = 0
        while start < frames {
            let end = min(start + block, frames)
            let n = Double(end - start)
            // How loud each mic is in this bit. Rises fast (a new speaker is
            // picked up within about 30 ms), falls slowly (no flapping
            // between words).
            for c in 0..<channels {
                var sum: Double = 0
                for i in start..<end { let v = Double(src[c][i]); sum += v * v }
                let now = sum / n
                let speed = now > level[c] ? 0.3 : 0.03
                level[c] += speed * (now - level[c])
            }
            // Louder mic wins: weight by level squared, so a mic twice as
            // loud (in sound) gets about 94%. Total silence keeps the last weights.
            let power = level.map { $0 * $0 }
            let total = power.reduce(0, +)
            let old = gain
            if total > 1e-18 {
                for c in 0..<channels { gain[c] += 0.25 * (power[c] / total - gain[c]) }
            }
            // Fade from the old weights to the new across the bit: no clicks.
            for i in start..<end {
                let t = Double(i - start + 1) / n
                var v: Double = 0
                for c in 0..<channels { v += (old[c] + (gain[c] - old[c]) * t) * Double(src[c][i]) }
                dst[i] = Float(v)
            }
            start = end
        }
        return out
    }

    /// "62% left, 38% right" style, for Copy Layout Details.
    var weightsText: String {
        gain.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: " / ")
    }
}

/// What the mic sent last time, for Help > Copy Layout Details (so Claude
/// can tell which mic Ryan used without asking). Any thread.
final class MicReport: @unchecked Sendable {
    static let shared = MicReport()
    private let lock = NSLock()
    private var name = "none yet"
    private var formatText = ""
    private var weights = ""

    func set(name: String) { lock.withLock { self.name = name; formatText = ""; weights = "" } }
    func set(format: AVAudioFormat) {
        let kind: String
        switch format.commonFormat {
        case .pcmFormatFloat32: kind = "float32"
        case .pcmFormatInt16: kind = "int16"
        case .pcmFormatInt32: kind = "int32"
        case .pcmFormatFloat64: kind = "float64"
        default: kind = "other"
        }
        let text = "\(format.channelCount) ch, \(Int(format.sampleRate)) Hz, \(kind)\(format.isInterleaved ? " interleaved" : "")"
        lock.withLock { formatText = text }
    }
    func set(weights: String) { lock.withLock { self.weights = weights } }

    var text: String {
        lock.withLock {
            var s = "MIC: \(name)"
            if !formatText.isEmpty { s += ", \(formatText)" }
            if !weights.isEmpty { s += ", louder mic weights \(weights)" }
            return s
        }
    }
}
