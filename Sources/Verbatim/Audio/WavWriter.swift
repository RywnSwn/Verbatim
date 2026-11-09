import Foundation

/// Writes 16 kHz mono 16-bit WAV, crash safe.
///
/// Samples go straight to disk. Every couple of seconds the header sizes are
/// patched and the file is synced, so after a crash at most ~2 s is lost, and
/// `repair` fixes the header from the real file length on next launch.
final class WavWriter {
    static let sampleRate: UInt32 = 16_000
    static let headerSize: UInt64 = 44

    let url: URL
    private let handle: FileHandle
    private(set) var dataBytes: UInt64
    private var lastFlush = Date()

    var samplesWritten: Int64 { Int64(dataBytes / 2) }

    /// Starts a new, empty file.
    init(creating url: URL) throws {
        self.url = url
        guard FileManager.default.createFile(atPath: url.path, contents: WavWriter.header(dataBytes: 0)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forUpdating: url)
        dataBytes = 0
        try handle.seekToEnd()
    }

    /// Opens an existing file (after Undo Stop or a crash) and keeps adding to it.
    init(appendingTo url: URL) throws {
        self.url = url
        handle = try FileHandle(forUpdating: url)
        let size = try handle.seekToEnd()
        if size < WavWriter.headerSize {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: WavWriter.header(dataBytes: 0))
            dataBytes = 0
        } else {
            // Drop half a sample if the crash cut one in two.
            dataBytes = (size - WavWriter.headerSize) & ~UInt64(1)
            try handle.truncate(atOffset: WavWriter.headerSize + dataBytes)
        }
        try patchHeader()
        try handle.seekToEnd()
    }

    func append(_ samples: UnsafeBufferPointer<Int16>) throws {
        guard samples.count > 0 else { return }
        let data = Data(buffer: samples) // Apple Silicon is little endian, same as WAV.
        try handle.write(contentsOf: data)
        dataBytes += UInt64(data.count)
        if Date().timeIntervalSince(lastFlush) >= 2 {
            try flush()
        }
    }

    func flush() throws {
        try patchHeader()
        try handle.synchronize()
        lastFlush = Date()
    }

    func close() throws {
        try flush()
        try handle.close()
    }

    /// Fixes the header of a file left behind by a crash. Returns the number of samples.
    static func repair(_ url: URL) throws -> Int64 {
        let writer = try WavWriter(appendingTo: url)
        let samples = writer.samplesWritten
        try writer.close()
        return samples
    }

    private func patchHeader() throws {
        let end = try handle.offset()
        let size = UInt32(clamping: dataBytes)
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: WavWriter.le32(36 &+ size))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: WavWriter.le32(size))
        try handle.seek(toOffset: end)
    }

    static func header(dataBytes: UInt32) -> Data {
        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8))
        d.append(le32(36 &+ dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        d.append(le32(16))            // fmt chunk size
        d.append(le16(1))             // PCM
        d.append(le16(1))             // mono
        d.append(le32(sampleRate))
        d.append(le32(sampleRate * 2)) // bytes per second
        d.append(le16(2))             // bytes per frame
        d.append(le16(16))            // bits per sample
        d.append(contentsOf: Array("data".utf8))
        d.append(le32(dataBytes))
        return d
    }

    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
