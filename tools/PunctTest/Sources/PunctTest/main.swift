@preconcurrency import AVFoundation
import FluidAudio
import Foundation

// Usage: PunctTest <audio file> [<audio file> ...]
// For each file prints four transcripts and a punctuation count:
//   live     StreamingUnifiedAsrManager fed 0.5 s at a time, tokens joined
//            the way ParakeetEngine.words does (what Verbatim shows today)
//   batch    UnifiedAsrManager over the whole file (after-Stop idea)
//   rolling  UnifiedAsrManager over each 60 s piece on its own (rolling idea)
//   tdtv3    Parakeet TDT v3 batch, for comparison

let files = Array(CommandLine.arguments.dropFirst())
let converter = AudioConverter()
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

func buffer(_ s: ArraySlice<Float>) -> AVAudioPCMBuffer {
    let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.count))!
    b.frameLength = AVAudioFrameCount(s.count)
    s.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: s.count) }
    return b
}

func stats(_ text: String) -> String {
    let words = text.split(whereSeparator: \.isWhitespace)
    let n = max(words.count, 1)
    func per100(_ c: Int) -> String { String(format: "%.1f", Double(c) * 100 / Double(n)) }
    let caps = words.filter { $0.first?.isUppercase == true }.count
    let commas = text.filter { $0 == "," }.count
    let stops = text.filter { ".?!".contains($0) }.count
    let quotes = text.filter { "\"“”".contains($0) }.count
    return "words \(words.count) | per 100 words: capitals \(per100(caps)), commas \(per100(commas)), . ? ! \(per100(stops)), quotes \(per100(quotes))"
}

func show(_ label: String, _ text: String, seconds: Double) {
    print("\n----- \(label) (\(String(format: "%.1f", seconds)) s) -----")
    print(stats(text))
    print(text)
}

func timed<T>(_ f: () async throws -> T) async throws -> (T, Double) {
    let t = Date()
    let r = try await f()
    return (r, Date().timeIntervalSince(t))
}

/// What Verbatim's live text does: 0.5 s pieces, tokens joined.
func liveText(_ live: StreamingUnifiedAsrManager, _ samples: [Float]) async throws -> String {
    try await live.reset()
    var text = ""
    var pos = 0
    while pos < samples.count {
        let end = min(pos + 8_000, samples.count)
        try await live.appendAudio(buffer(samples[pos..<end]))
        try await live.processBufferedAudio()
        text += await live.consumeTokenTimings().map(\.token).joined()
        pos = end
    }
    _ = try await live.finish()
    text += await live.consumeTokenTimings().map(\.token).joined()
    return text.trimmingCharacters(in: .whitespaces)
}

/// --two-mics <stereo file>: left only (before Nov 19), both averaged
/// (Nov 19), LouderMic (the app's own file, copied in by the workflow).
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--two-mics" {
    do {
        let live = StreamingUnifiedAsrManager()
        try await live.loadModels()
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[2]))
        let pf = file.processingFormat
        let stereo = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: stereo)
        let n = Int(stereo.frameLength)
        let ch = stereo.floatChannelData!
        print("two mics: \(pf.channelCount) ch, \(Int(pf.sampleRate)) Hz, \(n / Int(pf.sampleRate)) s")
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pf.sampleRate, channels: 1, interleaved: false)!
        func monoBuf(_ f: (Int) -> Float) -> AVAudioPCMBuffer {
            let b = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(n))!
            b.frameLength = AVAudioFrameCount(n)
            for i in 0..<n { b.floatChannelData![0][i] = f(i) }
            return b
        }
        let left = monoBuf { ch[0][$0] }
        let average = monoBuf { (ch[0][$0] + ch[1][$0]) / 2 }
        // Through LouderMic in 1024-frame pieces, like mic buffers.
        let mixer = LouderMic(rate: pf.sampleRate, channels: 2)!
        var louderSamples: [Float] = []
        var pos = 0
        while pos < n {
            let m = min(1024, n - pos)
            let piece = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(m))!
            piece.frameLength = AVAudioFrameCount(m)
            for c in 0..<2 { piece.floatChannelData![c].update(from: ch[c] + pos, count: m) }
            let out = mixer.mix(piece)!
            louderSamples += UnsafeBufferPointer(start: out.floatChannelData![0], count: m)
            pos += m
        }
        print("louder mic weights at the end: \(mixer.weightsText)")
        let louder = monoBuf { louderSamples[$0] }
        for (label, b) in [("left mic only (before Nov 19)", left), ("both averaged (Nov 19)", average), ("follow the louder mic (new)", louder)] {
            let s16 = try converter.resampleBuffer(b)
            let (text, sec) = try await timed { try await liveText(live, s16) }
            show(label, text, seconds: sec)
        }
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
    exit(0)
}

do {
    let live = StreamingUnifiedAsrManager()
    try await live.loadModels()
    let batch = UnifiedAsrManager()
    try await batch.loadModels()
    let tdtModels = try await AsrModels.downloadAndLoad(version: .v3)
    let tdt = AsrManager(config: .default)
    try await tdt.loadModels(tdtModels)

    for path in files {
        let samples = try converter.resampleAudioFile(URL(fileURLWithPath: path))
        print("\n================ \(URL(fileURLWithPath: path).lastPathComponent): \(samples.count / 16_000) s ================")

        let (liveText, liveSec) = try await timed { () async throws -> String in
            try await live.reset()
            var text = ""
            var pos = 0
            let step = 8_000
            while pos < samples.count {
                let end = min(pos + step, samples.count)
                try await live.appendAudio(buffer(samples[pos..<end]))
                try await live.processBufferedAudio()
                text += await live.consumeTokenTimings().map(\.token).joined()
                pos = end
            }
            _ = try await live.finish()
            text += await live.consumeTokenTimings().map(\.token).joined()
            return text.trimmingCharacters(in: .whitespaces)
        }
        show("live (today)", liveText, seconds: liveSec)

        let (batchText, batchSec) = try await timed { try await batch.transcribe(samples) }
        show("batch, whole file", batchText, seconds: batchSec)

        let (rollText, rollSec) = try await timed { () async throws -> String in
            var parts: [String] = []
            var pos = 0
            let minute = 60 * 16_000
            while pos < samples.count {
                let end = min(pos + minute, samples.count)
                parts.append(try await batch.transcribe(Array(samples[pos..<end])))
                pos = end
            }
            return parts.joined(separator: " ")
        }
        show("rolling batch, 60 s pieces", rollText, seconds: rollSec)

        let (tdtText, tdtSec) = try await timed { () async throws -> String in
            var state = TdtDecoderState.make(decoderLayers: await tdt.decoderLayerCount)
            return try await tdt.transcribe(samples, decoderState: &state).text
        }
        show("TDT v3 batch", tdtText, seconds: tdtSec)
    }
} catch {
    print("FAILED: \(error)")
    exit(1)
}
