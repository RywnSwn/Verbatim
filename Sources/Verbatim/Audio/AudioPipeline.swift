import AVFoundation

enum CaptureError: LocalizedError {
    case cannotUseMic
    var errorDescription: String? { "This microphone can't be used right now." }
}

/// Mic in, two mono Int16 files out, from the same sound:
/// - 16 kHz (audio.wav): what Parakeet and the speaker model hear, and live text.
/// - 48 kHz (listen.wav): only for listening back (Ryan, 2026-11-19: 16 kHz
///   sounded muffled). Nothing that makes text ever reads it.
/// The mic's own format comes in and Verbatim converts it. A stereo mic
/// (a 2-mic receiver in split mode: one mic left, one right) is mixed down,
/// so both mics are heard. (Before, macOS converted to mono and only the
/// left channel was kept.)
/// Everything that touches the writers runs on `sampleQueue`.
final class AudioPipeline: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessionQueue = DispatchQueue(label: "verbatim.session")
    private let sampleQueue = DispatchQueue(label: "verbatim.samples", qos: .userInitiated)
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(WavWriter.sampleRate), channels: 1, interleaved: true)!
    private let listenTarget = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(WavWriter.listenRate), channels: 1, interleaved: true)!

    private var session: AVCaptureSession?
    private var runtimeObserver: NSObjectProtocol?

    // sampleQueue only
    private var writer: WavWriter?
    private var listenWriter: WavWriter?
    private var converter: AVAudioConverter?
    private var listenConverter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private var sumSquares: Double = 0
    private var levelCount = 0
    private var failed = false

    /// Called on a background queue 20 times a second: level 0...1, samples so far.
    var onLevel: (@Sendable (Float, Int64) -> Void)?
    /// Called on a background queue when writing fails (disk full).
    var onWriteError: (@Sendable (Error) -> Void)?
    /// Called on the main queue when the capture session stops by itself.
    var onRuntimeError: (@Sendable () -> Void)?
    /// Called on the audio queue with every bit of audio that was saved, for live text.
    var onSamples: (@Sendable ([Float]) -> Void)?

    /// `listen`: the 48 kHz copy. nil = this recording has none (made
    /// before it existed); playback then uses the 16 kHz audio.
    func attach(_ writer: WavWriter, listen: WavWriter?) {
        sampleQueue.sync {
            self.writer = writer
            self.listenWriter = listen
            self.failed = false
            // Fresh converters: none of the last recording's sound carries over.
            self.converter = nil
            self.listenConverter = nil
        }
    }

    /// A write failed (disk full) and nothing is saved until this is cleared.
    var hasWriteError: Bool { sampleQueue.sync { failed } }

    /// Before Resume after a failed write: put the file back to its last
    /// good sample and save again. False if the file can't be fixed.
    /// (UX round 2, A3: Resume used to look like recording but save nothing.)
    func clearWriteError() -> Bool {
        sampleQueue.sync {
            guard failed else { return true }
            do {
                try writer?.recoverAfterError()
                failed = false
                return true
            } catch {
                return false
            }
        }
    }

    /// Stops capture, closes the file, returns the number of samples saved.
    @discardableResult
    func detach() -> Int64 {
        stopCapture()
        return sampleQueue.sync {
            let n = writer?.samplesWritten ?? 0
            try? writer?.close()
            try? listenWriter?.close()
            writer = nil
            listenWriter = nil
            return n
        }
    }

    func flush() {
        sampleQueue.sync {
            try? writer?.flush()
            try? listenWriter?.flush()
        }
    }

    var samplesWritten: Int64 {
        sampleQueue.sync { writer?.samplesWritten ?? 0 }
    }

    func startCapture(device: AVCaptureDevice) throws {
        stopCapture()
        let s = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard s.canAddInput(input) else { throw CaptureError.cannotUseMic }
        s.addInput(input)

        // No audioSettings: the mic's own format (rate and channels), so
        // the 48 kHz copy is real 48 kHz and every channel is kept for the mix.
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard s.canAddOutput(output) else { throw CaptureError.cannotUseMic }
        s.addOutput(output)

        runtimeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: s, queue: .main
        ) { [weak self] _ in
            self?.onRuntimeError?()
        }
        session = s
        sessionQueue.async { s.startRunning() }
    }

    func stopCapture() {
        if let o = runtimeObserver {
            NotificationCenter.default.removeObserver(o)
            runtimeObserver = nil
        }
        guard let s = session else { return }
        session = nil
        sessionQueue.sync { s.stopRunning() }
        // Let any buffers already in flight land in the file.
        sampleQueue.sync {}
    }

    // MARK: - Samples

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard writer != nil, !failed,
              let desc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0 else { return }
        let inFormat = AVAudioFormat(cmAudioFormatDescription: desc)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return }
        inBuf.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: inBuf.mutableAudioBufferList
        )
        guard status == noErr else { return }

        // A new mic (or the same one in a new format): new converters.
        if converter == nil || converterInput != inFormat {
            converter = Self.makeConverter(from: inFormat, to: target)
            listenConverter = Self.makeConverter(from: inFormat, to: listenTarget)
            converterInput = inFormat
        }
        guard let converter, let out = Self.convert(inBuf, with: converter, to: target) else { return }
        deliver(out)
        if listenWriter != nil, let listenConverter,
           let listen = Self.convert(inBuf, with: listenConverter, to: listenTarget) {
            deliverListen(listen)
        }
    }

    private static func makeConverter(from input: AVAudioFormat, to output: AVAudioFormat) -> AVAudioConverter? {
        let c = AVAudioConverter(from: input, to: output)
        c?.downmix = true // stereo mic: both channels, not just the left one
        c?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        return c
    }

    /// One buffer through a converter that keeps its state between buffers
    /// (so the resampler doesn't click at every buffer edge).
    private static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(input.frameLength) * format.sampleRate / input.format.sampleRate) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let result = converter.convert(to: outBuf, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard result != .error else { return nil }
        return outBuf
    }

    /// The listening copy. If it can't be written, it's dropped and the
    /// recording carries on: playback uses the 16 kHz audio instead.
    private func deliverListen(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.int16ChannelData, let listenWriter else { return }
        do {
            try listenWriter.append(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        } catch {
            try? listenWriter.close()
            try? FileManager.default.removeItem(at: listenWriter.url)
            self.listenWriter = nil
        }
    }

    private func deliver(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.int16ChannelData, let writer else { return }
        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        do {
            try writer.append(samples)
        } catch {
            failed = true
            onWriteError?(error)
            return
        }
        onSamples?(samples.map { Float($0) / 32_768 })
        for s in samples {
            let v = Double(s)
            sumSquares += v * v
        }
        levelCount += samples.count
        if levelCount >= 800 { // 1/20 s at 16 kHz: the waveform moves 20 bars a second
            let rms = (sumSquares / Double(levelCount)).squareRoot() / 32_768
            let db = 20 * log10(max(rms, 1e-7))
            let level = Float(min(max((db + 55) / 45, 0), 1))
            sumSquares = 0
            levelCount = 0
            onLevel?(level, writer.samplesWritten)
        }
    }
}
