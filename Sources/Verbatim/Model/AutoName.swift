import Foundation
import FoundationModels

/// Names a recording from what was said (step 10, Ryan's ask), like
/// "Anansi and the sky god", with Apple's on-device model (Apple
/// Intelligence). Runs on the Mac, offline, free. Only renames recordings
/// whose name Verbatim made ("Wed 12 Nov" or a file name), once, after the
/// text is final. Ryan's own names are never touched.
@MainActor
final class AutoName {
    static let shared = AutoName()
    static let enabledKey = "autoName"

    /// Needs at least this many words to say what a class was about.
    private static let minWords = 80
    /// The on-device model reads about 4,000 tokens; stay well under.
    private static let maxWords = 1_200

    private var queue: [UUID] = []
    private var tried: Set<UUID> = []
    private var working = false

    private init() {}

    static var isOn: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// nil when it can run, else why not, in plain words for Settings.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use this."
            case .modelNotReady:
                return "Apple Intelligence is still downloading or getting ready. It starts working by itself."
            case .deviceNotEligible:
                return "This Mac can't run Apple Intelligence."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        }
    }

    /// At launch: anything that stopped before it got a name.
    func considerAll(_ recordings: [RecordingInfo]) {
        for r in recordings where r.autoTitle == true && !r.isActive { consider(r.id) }
    }

    /// Call when a recording's text is final (Undo Stop over, or a file is done).
    func consider(_ id: UUID) {
        guard Self.isOn, !tried.contains(id), !queue.contains(id) else { return }
        queue.append(id)
        runNext()
    }

    private func runNext() {
        guard !working, let id = queue.first else { return }
        queue.removeFirst()
        guard let text = readyText(id) else {
            runNext()
            return
        }
        tried.insert(id)
        working = true
        Task {
            let title = await Self.makeTitle(text)
            if let title { RecorderModel.shared.setAutoTitle(id, title) }
            working = false
            runNext()
        }
    }

    /// The transcript to read, or nil if it isn't time (or there's too little).
    private func readyText(_ id: UUID) -> String? {
        let model = RecorderModel.shared
        let t = Transcriber.shared
        guard Self.unavailableReason == nil,
              let info = model.info(id), info.autoTitle == true, id != model.currentID,
              t.active?.id != id, !t.isQueued(id), !t.importing.contains(id), !t.isGrowing(id) else { return nil }
        let lines = model.shownLines(id).map(\.line.text)
        let total = lines.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
        guard total >= Self.minWords else { return nil }
        // Long classes: take lines spread across the whole class, not just the start.
        guard total > Self.maxWords else { return lines.joined(separator: "\n") }
        let every = Int((Double(total) / Double(Self.maxWords)).rounded(.up))
        let picked = lines.enumerated().filter { $0.offset % every == 0 }.map(\.element)
        return picked.joined(separator: "\n")
    }

    private static func makeTitle(_ transcript: String) async -> String? {
        let session = LanguageModelSession(instructions: """
            You name recordings of school classes. Reply with only a short title of \
            2 to 6 words that says what the class was about, like "Anansi and the sky god" \
            or "How volcanoes form". No quotes, no date, no subject name, no full stop.
            """)
        do {
            let response = try await session.respond(
                to: "Transcript:\n\(transcript)\n\nTitle:",
                options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 30)
            )
            return clean(response.content)
        } catch {
            return nil
        }
    }

    /// First line, no quotes or full stop, not too long.
    static func clean(_ raw: String) -> String? {
        var s = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if s.lowercased().hasPrefix("title:") { s = String(s.dropFirst(6)) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \"'\u{201C}\u{201D}\u{2018}\u{2019}*.#"))
        guard s.count >= 3, s.split(separator: " ").count <= 10 else { return nil }
        if s.count > 60 { s = String(s.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
