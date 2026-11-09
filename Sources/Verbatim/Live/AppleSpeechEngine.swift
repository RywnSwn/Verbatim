@preconcurrency import AVFoundation
import Foundation
import Speech

/// Apple's built-in speech engine (SpeechAnalyzer, new in macOS 26). Only used
/// while Parakeet is still downloading. Its model is shared by the whole Mac and
/// runs outside Verbatim, so it costs Verbatim almost no memory.
actor AppleSpeechEngine: LiveEngine {
    static let name = "Apple"

    enum Readiness: Equatable { case ready, needsDownload, unavailable }

    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var finals: [LivePiece] = []
    private var volatile: String?
    private let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    private static func locale() async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    static func readiness() async -> Readiness {
        guard SpeechTranscriber.isAvailable, let locale = await locale() else { return .unavailable }
        switch await AssetInventory.status(forModules: [makeTranscriber(locale)]) {
        case .installed: return .ready
        case .supported, .downloading: return .needsDownload
        default: return .unavailable
        }
    }

    /// Asks macOS to download Apple's English speech model (shared by the whole Mac).
    static func install() async throws {
        guard let locale = await locale() else { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber(locale)]) {
            try await request.downloadAndInstall()
        }
    }

    /// macOS asks once: "Verbatim would like to use speech recognition".
    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    func begin() async throws {
        await stopAnalyzer()
        guard let locale = await Self.locale() else { throw CocoaError(.featureUnsupported) }
        let transcriber = Self.makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CocoaError(.featureUnsupported)
        }
        targetFormat = format
        converter = format == sourceFormat ? nil : AVAudioConverter(from: sourceFormat, to: format)
        converter?.primeMethod = .none

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        self.analyzer = analyzer
        finals = []
        volatile = nil
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    await self?.receive(text: text, start: start.isFinite ? start : 0, end: end.isFinite ? end : 0, isFinal: result.isFinal)
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)
    }

    private func receive(text: String, start: Double, end: Double, isFinal: Bool) {
        if isFinal {
            finals.append(LivePiece(text: text, start: start, end: end))
            volatile = ""
        } else {
            volatile = text
        }
    }

    func feed(_ samples: [Float]) async -> LiveOutput {
        if let buffer = convert(samples) {
            input?.yield(AnalyzerInput(buffer: buffer))
        }
        return drain()
    }

    func end() async -> LiveOutput {
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        var out = drain()
        out.volatile = ""
        return out
    }

    private func stopAnalyzer() async {
        input?.finish()
        input = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
    }

    private func drain() -> LiveOutput {
        defer {
            finals.removeAll()
            volatile = nil
        }
        return LiveOutput(finals: finals, volatile: volatile)
    }

    private func convert(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let src = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = src.floatChannelData?[0] else { return nil }
        src.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        guard let converter, let targetFormat else { return src }

        let capacity = AVAudioFrameCount(Double(samples.count) * targetFormat.sampleRate / sourceFormat.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return src
        }
        return status == .error ? nil : out
    }
}
