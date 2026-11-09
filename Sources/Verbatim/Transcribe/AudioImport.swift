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

    static func canImport(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Runs off the main thread. Returns the number of samples written.
    static func convert(_ source: URL, to destination: URL) async throws -> Int64 {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ImportError.noAudio }

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
        while let buffer = output.copyNextSampleBuffer() {
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
        }
        if reader.status == .failed {
            try? writer.close()
            throw reader.error ?? ImportError.noAudio
        }
        try writer.close()
        return writer.samplesWritten
    }
}
