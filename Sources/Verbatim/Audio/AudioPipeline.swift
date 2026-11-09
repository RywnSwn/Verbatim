import AVFoundation

enum CaptureError: LocalizedError {
    case cannotUseMic
    var errorDescription: String? { "This microphone can't be used right now." }
}

/// Mic in, 16 kHz mono Int16 samples out, written to a WavWriter.
/// Everything that touches the writer runs on `sampleQueue`.
final class AudioPipeline: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessionQueue = DispatchQueue(label: "verbatim.session")
    private let sampleQueue = DispatchQueue(label: "verbatim.samples", qos: .userInitiated)
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private var session: AVCaptureSession?
    private var runtimeObserver: NSObjectProtocol?

    // sampleQueue only
    private var writer: WavWriter?
    private var converter: AVAudioConverter?
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

    func attach(_ writer: WavWriter) {
        sampleQueue.sync {
            self.writer = writer
            self.failed = false
        }
    }

    /// Stops capture, closes the file, returns the number of samples saved.
    @discardableResult
    func detach() -> Int64 {
        stopCapture()
        return sampleQueue.sync {
            let n = writer?.samplesWritten ?? 0
            try? writer?.close()
            writer = nil
            return n
        }
    }

    func flush() {
        sampleQueue.sync { try? writer?.flush() }
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

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
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

        if inFormat == target {
            deliver(inBuf)
            return
        }
        // The mic gave us another format: convert to 16 kHz mono Int16.
        if converter == nil || converterInput != inFormat {
            converter = AVAudioConverter(from: inFormat, to: target)
            converterInput = inFormat
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(frames) * target.sampleRate / inFormat.sampleRate) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        let result = converter.convert(to: outBuf, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return inBuf
        }
        guard result != .error else { return }
        deliver(outBuf)
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
