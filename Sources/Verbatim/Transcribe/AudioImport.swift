import AVFoundation

/// Copies the sound from a Voice Memo (or other file) into our own 16 kHz WAV.
/// The original file is only read, never changed.
enum AudioImport {
    static let allowedExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "caf", "mp4", "mov", "m4v"]
    static let allowedText = ".m4a (Voice Memos), .mp3, .wav, .mp4 or .mov"

    enum ImportError: LocalizedError {
        case noAudio
        var errorDescription: String? { "This file has no sound in it." }
    }

    /// An import error in plain words (C3: it showed "OSStatus error -11829").
    static func plainWords(_ error: Error) -> String {
        if let e = error as? ImportError { return e.errorDescription ?? "" }
        let ns = error as NSError
        if ns.domain == NSOSStatusErrorDomain || ns.domain == AVFoundationErrorDomain {
            return "the sound in it couldn't be read. The file may be damaged, or a kind Verbatim can't open."
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError {
            return "Verbatim isn't allowed to open it. Drag it onto the window instead."
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError {
            return "the disk is full."
        }
        return error.localizedDescription
    }

    static func canImport(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Runs off the main thread. Returns the number of samples written.
    /// `progress` gets 0 to 1 now and then. Stops with CancellationError when
    /// its task is cancelled (Cancel, or the recording was deleted).
    static func convert(_ source: URL, to destination: URL,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Int64 {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ImportError.noAudio }
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let expected = seconds.isFinite && seconds > 0 ? seconds * 16_000 : 0

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ImportError.noAudio }

        let writer = try WavWriter(creating: destination)
        var told = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                try? writer.close()
                throw CancellationError()
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            try data.withUnsafeBytes { raw in
                try writer.append(raw.bindMemory(to: Int16.self))
            }
            if expected > 0 {
                let f = min(Double(writer.samplesWritten) / expected, 1)
                if f - told >= 0.01 {
                    told = f
                    progress(f)
                }
            }
        }
        if reader.status == .failed {
            try? writer.close()
            throw reader.error ?? ImportError.noAudio
        }
        try writer.close()
        return writer.samplesWritten
    }
}
