@preconcurrency import AVFoundation
import Foundation
import Observation

/// Shrinks a recording's audio after Stop (Ryan's ask). Two full-size WAVs
/// (crash safe while recording) become AAC in .m4a, the format Voice Memos
/// uses:
/// - audio.wav, 16 kHz, what Parakeet reads: 32 kbps, about 14 MB per hour
///   (as before, so text made from it later doesn't change).
/// - listen.wav, 48 kHz, for listening: 64 kbps, about 29 MB per hour. A
///   gentle squeeze: it still sounds like the room (Ryan picked 48 kHz and
///   ~45 MB per hour for both, 2026-11-19).
///
/// Waits until the recording is final (the 10 s Undo Stop is over) and the
/// file isn't being transcribed. One at a time, never while recording.
/// The WAV is deleted only after the new file has been checked.
@MainActor
@Observable
final class AudioSquash {
    static let shared = AudioSquash()

    /// The recording being shrunk right now.
    private(set) var working: UUID?

    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {}

    /// Looks for recordings that still have a WAV and shrinks them, one by
    /// one. Safe to call often.
    func run() {
        guard task == nil else { return }
        task = Task {
            while let id = nextID() {
                working = id
                let jobs = [
                    (RecordingStore.wavURL(id), RecordingStore.m4aURL(id), Self.textBitRates),
                    (RecordingStore.listenWavURL(id), RecordingStore.listenM4aURL(id), Self.listenBitRates),
                ].filter { FileManager.default.fileExists(atPath: $0.0.path) }
                var ok = true
                for (wav, m4a, rates) in jobs {
                    let done = await Task.detached(priority: .utility) { Self.squash(wav, to: m4a, bitRates: rates) }.value
                    ok = ok && done
                }
                working = nil
                // Something odd (disk full, unreadable file): keep the WAV and
                // don't try that one again until next launch.
                if !ok { skipped.insert(id) }
            }
            task = nil
        }
    }

    @ObservationIgnored private var skipped: Set<UUID> = []

    private func nextID() -> UUID? {
        let model = RecorderModel.shared
        let t = Transcriber.shared
        guard !model.isBusy, t.growing.isEmpty else { return nil }
        return model.recordings.first { r in
            r.hasAudio && !r.isActive && r.id != model.currentID && !skipped.contains(r.id)
                && (FileManager.default.fileExists(atPath: RecordingStore.wavURL(r.id).path)
                    || FileManager.default.fileExists(atPath: RecordingStore.listenWavURL(r.id).path))
                && t.active?.id != r.id && !t.isQueued(r.id) && !t.importing.contains(r.id)
                && model.stoppedNote?.recordingID != r.id
        }?.id
    }

    /// 32 kbps is plenty for Parakeet at 16 kHz. If the Mac's encoder won't
    /// take it, try lower, then its own default (0).
    nonisolated static let textBitRates = [32_000, 24_000, 0]
    /// The listening copy: 64 kbps mono at 48 kHz keeps voices clear.
    nonisolated static let listenBitRates = [64_000, 96_000, 0]

    /// Off the main thread. True when the m4a is in place and the WAV is gone.
    nonisolated private static func squash(_ wav: URL, to m4a: URL, bitRates: [Int]) -> Bool {
        let temp = m4a.deletingLastPathComponent().appending(path: m4a.deletingPathExtension().lastPathComponent + "-shrinking.m4a")
        // Left over if the app quit or crashed partway through last time.
        try? FileManager.default.removeItem(at: temp)
        do {
            let input = try AVAudioFile(forReading: wav)
            let format = input.processingFormat
            // Quit or crashed after the new file was put in place but before
            // the WAV was deleted. If that m4a is whole, just finish the job;
            // if not, it goes and the WAV is shrunk again. (Before, the move
            // below failed because the m4a was there, so it never finished
            // and started over at every launch.)
            if FileManager.default.fileExists(atPath: m4a.path) {
                if isWhole(m4a, expected: input.length, rate: format.sampleRate) {
                    input.close()
                    try FileManager.default.removeItem(at: wav)
                    return true
                }
                try FileManager.default.removeItem(at: m4a)
            }
            var output: AVAudioFile?
            for bitRate in bitRates {
                var settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: 1,
                ]
                if bitRate > 0 { settings[AVEncoderBitRateKey] = bitRate }
                try? FileManager.default.removeItem(at: temp)
                if let f = try? AVAudioFile(forWriting: temp, settings: settings,
                                            commonFormat: .pcmFormatFloat32, interleaved: false) {
                    output = f
                    break
                }
            }
            guard let output else { return false }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000) else { return false }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
            let expected = input.length
            output.close()
            input.close()

            // Check the new file before throwing the old one away.
            guard isWhole(temp, expected: expected, rate: format.sampleRate) else {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
            try FileManager.default.moveItem(at: temp, to: m4a)
            try FileManager.default.removeItem(at: wav)
            return true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
    }
}

extension AudioSquash {
    /// The shrunk file opens and is as long as the WAV (within 1%, plus a
    /// second for the encoder's padding).
    nonisolated private static func isWhole(_ url: URL, expected: Int64, rate: Double) -> Bool {
        guard let check = try? AVAudioFile(forReading: url) else { return false }
        let got = check.length
        check.close()
        return expected == 0 || abs(Double(got - expected)) < Double(expected) * 0.01 + rate
    }
}

/// Reads a recording's audio (WAV or the squashed m4a) as 16 kHz mono Floats.
/// Opened once, so the file can be squashed or deleted while it's read.
final class AudioReader {
    let file: AVAudioFile
    let rate: Double
    var length: Int64 { file.length }

    init(_ url: URL) throws {
        file = try AVAudioFile(forReading: url)
        rate = file.processingFormat.sampleRate
        guard rate == 16_000, file.processingFormat.channelCount == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func samples(from start: Int64, count: Int64) throws -> [Float] {
        file.framePosition = start
        let n = AVAudioFrameCount(max(0, min(count, file.length - start)))
        guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: n) else { return [] }
        try file.read(into: buffer, frameCount: n)
        guard let data = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
}
