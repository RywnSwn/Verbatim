import Foundation
import Observation

/// Voice memory (step 7c). When Ryan gives a speaker a real name, about 20
/// seconds of that voice is saved here (on this Mac only). Every new
/// recording, file pass or "Find speakers" first plays these clips to the
/// speaker model (Sortformer "enrollment"), so a known voice gets its name
/// from the first line instead of "Speaker 1".
///
/// Files: App Support/Verbatim/Voices/voices.json (the list) and
/// <id>.f32 (16 kHz mono Float samples, ~1.3 MB each).
@MainActor
@Observable
final class VoiceLibrary {
    static let shared = VoiceLibrary()

    /// Sortformer has 4 voice slots. Known voices take at most 3, so at
    /// least one is always free for everyone else.
    static let maxInUse = 3
    /// Seconds of voice saved: enough for the model, small on disk.
    static let clipSeconds = 20.0
    /// Below this the voice is too short to be worth remembering.
    static let minSeconds = 6.0

    struct Voice: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// Recording it came from, for Settings ("from English, Mon 10 Nov").
        var from: String
        var savedAt = Date()
        var seconds: Double
        /// Ryan can switch a voice off without forgetting it.
        var enabled = true
    }

    private(set) var voices: [Voice] = []

    private init() {
        if let data = try? Data(contentsOf: Self.listURL),
           let list = try? JSONDecoder().decode([Voice].self, from: data) {
            voices = list
        }
    }

    /// The voices to play to the speaker model, newest first.
    var inUse: [Voice] { Array(voices.filter(\.enabled).sorted { $0.savedAt > $1.savedAt }.prefix(Self.maxInUse)) }

    nonisolated static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appending(path: "Verbatim/Voices", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated private static var listURL: URL { folder.appending(path: "voices.json") }

    nonisolated static func clipURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).f32") }

    /// The saved samples of a voice.
    nonisolated static func samples(_ id: UUID) -> [Float]? {
        guard let data = try? Data(contentsOf: clipURL(id)), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func saveList() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(voices).write(to: Self.listURL, options: .atomic)
    }

    // MARK: - Remembering

    /// Ryan named a voice in a recording: save a clip of it. Replaces an older
    /// voice with the same name (newer is closer to how they sound now).
    /// Returns the voice that was there before (for Undo), or nil.
    /// Runs the audio reading off the main thread; `done` gets true if saved.
    func remember(name: String, voice: Int, in info: RecordingInfo, done: @escaping @MainActor (Bool) -> Void) {
        guard info.hasAudio, Speakers.voice(of: name) == nil else { return done(false) }
        let lines = LiveTranscriber.shared.lines(info.id).filter { $0.voice == voice && $0.speaker == nil }
        // Longest lines first: more of the voice, less of anyone else.
        let spans = lines.sorted { ($0.end - $0.start) > ($1.end - $1.start) }.map { ($0.start, $0.end) }
        let id = info.id
        let title = info.fullTitle
        Task.detached(priority: .utility) {
            let clip = Self.clip(id, spans: spans)
            await MainActor.run {
                let seconds = Double(clip.count) / 16_000
                guard seconds >= Self.minSeconds else { return done(false) }
                let new = Voice(name: name, from: title, seconds: seconds)
                do {
                    try clip.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: Self.clipURL(new.id), options: .atomic)
                } catch {
                    return done(false)
                }
                let replaced = self.voices.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                self.voices.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                self.voices.append(new)
                self.saveList()
                for old in replaced { try? FileManager.default.removeItem(at: Self.clipURL(old.id)) }
                done(true)
            }
        }
    }

    /// Up to `clipSeconds` of audio from the spans, at most 8 s from each,
    /// skipping the first and last bit of each line (where voices overlap).
    nonisolated private static func clip(_ id: UUID, spans: [(Double, Double)]) -> [Float] {
        let wav = RecordingStore.wavURL(id)
        let useWav = FileManager.default.fileExists(atPath: wav.path)
        let reader = useWav ? nil : try? AudioReader(RecordingStore.audioURL(id))
        guard useWav || reader != nil else { return [] }
        var out: [Float] = []
        let limit = Int(clipSeconds * 16_000)
        for (start, end) in spans {
            let a = start + 0.3, b = min(end - 0.3, a + 8)
            guard b - a >= 1.5 else { continue }
            let from = Int64(a * 16_000), count = Int64((b - a) * 16_000)
            let piece = useWav
                ? (try? WavReader.samples(wav, from: from, count: count)) ?? []
                : (try? reader?.samples(from: from, count: count)) ?? []
            out += piece.prefix(limit - out.count)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Settings

    func forget(_ id: UUID) {
        voices.removeAll { $0.id == id }
        saveList()
        try? FileManager.default.removeItem(at: Self.clipURL(id))
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = voices.firstIndex(where: { $0.id == id }) else { return }
        voices[i].enabled = on
        saveList()
    }

    /// Undo of a remember: forget the new one (the replaced clip is gone, so
    /// the older voice can't come back; Ryan can name it again).
    func forget(named name: String, savedAfter date: Date) {
        for v in voices where v.name.caseInsensitiveCompare(name) == .orderedSame && v.savedAt >= date { forget(v.id) }
    }
}

/// A saved voice, ready for the speaker engine (off the main thread).
struct KnownVoice: Sendable {
    var name: String
    var samples: [Float]
}

extension VoiceLibrary {
    /// The voices in use with their audio, for SpeakerEngine.begin.
    func knownVoices() -> [KnownVoice] {
        inUse.compactMap { v in VoiceLibrary.samples(v.id).map { KnownVoice(name: v.name, samples: $0) } }
    }
}
