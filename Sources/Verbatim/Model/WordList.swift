import Foundation
import Observation

/// "Write `to` whenever `from` is heard." Whole words, any case. Used for Ryan's
/// fix rules and for the name fixes the word spotter sends (step 8).
struct PhraseFix: Codable, Hashable, Sendable, Identifiable {
    var from: String
    var to: String
    var id: String { Fixes.keys(from).joined(separator: " ") }
}

/// Step 8: the word list (names Parakeet listens for, through FluidAudio's
/// vocabulary boosting) and fix rules (find and replace for whatever it still
/// misses). Saved in App Support/Verbatim/words.json.
@MainActor
@Observable
final class WordList {
    static let shared = WordList()

    /// Known hard names from Ryan's English class.
    static let startingWords = ["Anansi", "Nyankupon", "Kweku Tsin"]
    static let startingFixes = [
        PhraseFix(from: "Father Nazi", to: "Anansi"),
        PhraseFix(from: "group bonds", to: "Nyankupon"),
    ]
    /// FluidAudio skips terms shorter than this.
    static let minLetters = 3
    static let maxLength = 40

    private struct Saved: Codable {
        var formatVersion = 1
        var words: [String]
        var fixes: [PhraseFix]
    }

    private(set) var words: [String]
    private(set) var fixes: [PhraseFix]

    private static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appending(path: "Verbatim", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "words.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            words = saved.words
            fixes = saved.fixes
        } else {
            words = Self.startingWords
            fixes = Self.startingFixes
            save()
        }
    }

    /// What Parakeet should listen for. Empty until the word spotter is downloaded.
    var boostTerms: [String] { WordModel.shared.isReady ? words : [] }

    // MARK: - Word list

    enum AddResult: Equatable {
        case added(String)
        case alreadyThere(String)
        case problem(String)
    }

    static func clean(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Why a word can't go in the list, or nil if it's fine.
    static func problem(with word: String) -> String? {
        let letters = word.filter { $0.isLetter || $0.isNumber }.count
        if word.isEmpty { return "Type a name or word first." }
        if letters < minLetters { return "Too short to listen for. Use \(minLetters) letters or more." }
        if word.count > maxLength { return "Too long. Use a name or a short phrase." }
        return nil
    }

    @discardableResult
    func addWord(_ raw: String) -> AddResult {
        let word = Self.clean(raw)
        if let problem = Self.problem(with: word) { return .problem(problem) }
        if let existing = words.first(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            return .alreadyThere(existing)
        }
        words.append(word)
        save()
        WordModel.shared.startIfNeeded()
        return .added(word)
    }

    /// Returns where it was, for Undo.
    @discardableResult
    func removeWord(_ word: String) -> Int? {
        guard let i = words.firstIndex(of: word) else { return nil }
        words.remove(at: i)
        save()
        return i
    }

    func insertWord(_ word: String, at i: Int) {
        guard !words.contains(word) else { return }
        words.insert(word, at: min(i, words.count))
        save()
    }

    // MARK: - Fix rules

    /// Why a fix can't be saved, or nil if it's fine.
    static func problem(with fix: PhraseFix) -> String? {
        if Fixes.keys(fix.from).isEmpty || Fixes.keys(fix.to).isEmpty { return "Fill in both sides." }
        if Fixes.keys(fix.from) == Fixes.keys(fix.to) { return "Both sides are the same word." }
        if fix.from.count > 60 || fix.to.count > 60 { return "Too long. Fixes are for a few words." }
        return nil
    }

    func fix(for from: String) -> PhraseFix? {
        let key = Fixes.keys(from)
        return fixes.first { Fixes.keys($0.from) == key }
    }

    /// Adds a rule, or changes the one with the same left side. Returns the old
    /// rule it replaced (for Undo), or nil.
    @discardableResult
    func addFix(_ raw: PhraseFix) -> PhraseFix? {
        let fix = PhraseFix(from: Self.clean(raw.from), to: Self.clean(raw.to))
        if let i = fixes.firstIndex(where: { $0.id == fix.id }) {
            let old = fixes[i]
            fixes[i] = fix
            save()
            return old
        }
        fixes.append(fix)
        save()
        return nil
    }

    @discardableResult
    func removeFix(_ fix: PhraseFix) -> Int? {
        guard let i = fixes.firstIndex(of: fix) else { return nil }
        fixes.remove(at: i)
        save()
        return i
    }

    func insertFix(_ fix: PhraseFix, at i: Int) {
        guard !fixes.contains(where: { $0.id == fix.id }) else { return }
        fixes.insert(fix, at: min(i, fixes.count))
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(Saved(words: words, fixes: fixes)).write(to: Self.url, options: .atomic)
    }
}

/// Text work for fixes: whole words, any case, punctuation kept.
enum Fixes {
    /// "Anansi," -> "anansi". Letters, numbers and apostrophes only.
    static func key<S: StringProtocol>(_ word: S) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" })
    }

    static func keys(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { key($0) }.filter { !$0.isEmpty }
    }

    /// Replaces `fix.from` with `fix.to` in a line. `onlyLast`: just the last
    /// match (the word spotter's fixes, one per occurrence). Word times follow
    /// along. nil when nothing changed.
    static func apply(_ fix: PhraseFix, to line: Transcript.Line, onlyLast: Bool = false) -> Transcript.Line? {
        let from = keys(fix.from)
        let to = fix.to.split(whereSeparator: \.isWhitespace).map(String.init)
        let toKeys = to.map { key($0) }
        guard !from.isEmpty, !to.isEmpty else { return nil }
        var words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        var lineKeys = words.map { key($0) }
        var times = line.words?.count == words.count ? line.words : nil
        let n = from.count

        func matches(_ i: Int) -> Bool {
            guard i >= 0, i + n <= words.count, Array(lineKeys[i..<i + n]) == from else { return false }
            // Already fixed: the replacement holds the same words (like
            // "Yurt" -> "Mr. Yurt"), so don't do it again.
            for j in 0...max(0, toKeys.count - n) where toKeys.count >= n && Array(toKeys[j..<j + n]) == from {
                let s = i - j
                if s >= 0, s + toKeys.count <= words.count, Array(lineKeys[s..<s + toKeys.count]) == toKeys { return false }
            }
            return true
        }

        func replace(at i: Int) {
            let first = words[i], last = words[i + n - 1]
            let lead = String(first.prefix { !($0.isLetter || $0.isNumber) })
            let trail = String(last.reversed().prefix { !($0.isLetter || $0.isNumber) }.reversed())
            var new = to
            if let c = first.first(where: { $0.isLetter }), c.isUppercase, let f = new[0].first, f.isLowercase {
                new[0] = f.uppercased() + new[0].dropFirst()
            }
            new[0] = lead + new[0]
            new[new.count - 1] += trail
            if var t = times {
                let a = t[i], b = t[i + n - 1]
                let m = new.count
                let spread = (0..<m).map { k in m > 1 ? ((a + (b - a) * Double(k) / Double(m - 1)) * 100).rounded() / 100 : a }
                t.replaceSubrange(i..<i + n, with: spread)
                times = t
            }
            words.replaceSubrange(i..<i + n, with: new)
            lineKeys.replaceSubrange(i..<i + n, with: new.map { key($0) })
        }

        var changed = false
        if onlyLast {
            for i in stride(from: words.count - n, through: 0, by: -1) where matches(i) {
                replace(at: i)
                changed = true
                break
            }
        } else {
            var i = 0
            while i + n <= words.count {
                if matches(i) {
                    replace(at: i)
                    changed = true
                    i += to.count
                } else {
                    i += 1
                }
            }
        }
        guard changed else { return nil }
        var out = line
        out.text = words.joined(separator: " ")
        out.words = times
        return out
    }

    /// Ryan's rules over the newest lines (the ones words were just added to).
    /// Locked lines and the line being edited are left alone.
    static func applyRules(_ rules: [PhraseFix], to lines: inout [Transcript.Line], last count: Int = 2, skip: Double? = nil) {
        guard !rules.isEmpty else { return }
        for i in lines.indices.suffix(count) where !lines[i].isLocked && lines[i].start != skip {
            for rule in rules {
                if let fixed = apply(rule, to: lines[i]) { lines[i] = fixed }
            }
        }
    }

    /// A fix from the word spotter: the newest line that still has the words
    /// it heard wrong (it reports about 15 s after the words show up).
    static func applySpotted(_ fix: PhraseFix, to lines: inout [Transcript.Line], skip: Double? = nil) {
        for i in lines.indices.reversed().prefix(40) where !lines[i].isLocked && lines[i].start != skip {
            if let fixed = apply(fix, to: lines[i], onlyLast: true) {
                lines[i] = fixed
                return
            }
        }
    }

    /// After Ryan edits a line: the few words he changed, if it looks like a
    /// mishearing worth remembering ("Father Nazi" to "Anansi").
    static func offer(old: String, new: String) -> PhraseFix? {
        let a = old.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = new.split(whereSeparator: \.isWhitespace).map(String.init)
        let ak = a.map { key($0) }, bk = b.map { key($0) }
        var p = 0
        while p < a.count, p < b.count, ak[p] == bk[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, ak[a.count - 1 - s] == bk[b.count - 1 - s] { s += 1 }
        let from = Array(a[p..<a.count - s]), to = Array(b[p..<b.count - s])
        guard (1...4).contains(from.count), (1...4).contains(to.count) else { return nil }
        let fromKeys = from.map { key($0) }.filter { !$0.isEmpty }
        let toKeys = to.map { key($0) }.filter { !$0.isEmpty }
        guard !fromKeys.isEmpty, !toKeys.isEmpty, fromKeys != toKeys else { return nil }
        // "a" to "the" is a grammar fix, not a mishearing.
        if fromKeys.count == 1, fromKeys[0].count <= 3 { return nil }
        let fix = PhraseFix(from: trimmed(from.joined(separator: " ")), to: trimmed(to.joined(separator: " ")))
        return fix
    }

    /// Punctuation off both ends: "Nazi," -> "Nazi".
    private static func trimmed(_ s: String) -> String {
        let keep: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = s.firstIndex(where: keep), let last = s.lastIndex(where: keep) else { return s }
        return String(s[first...last])
    }

    /// Words in `to` that look like a name (capital letter), for the word list.
    static func looksLikeName(_ s: String) -> Bool {
        s.split(whereSeparator: \.isWhitespace).contains { $0.first?.isUppercase == true }
    }
}

/// The word spotter download (Parakeet CTC 110M, about 100 MB, step 8). Like
/// the speaker model: it comes after Parakeet and the speaker model, and only
/// when the word list has something in it. Until it's here, fix rules still work.
@MainActor
@Observable
final class WordModel {
    static let shared = WordModel()

    enum State: Equatable {
        case waiting
        case downloading(fraction: Double)
        case failed(fraction: Double)
        case preparing
        case ready
    }

    private(set) var state: State = .waiting
    var isReady: Bool { state == .ready }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    private static let preparedKey = "wordModelPrepared"

    private init() {
        if UserDefaults.standard.bool(forKey: Self.preparedKey), ParakeetEngine.wordSpotterOnDisk { state = .ready }
    }

    /// Called at launch, when the speaker model is ready and when a word is added.
    func startIfNeeded() {
        guard state != .ready, state != .preparing, task == nil,
              LiveTranscriber.shared.isModelReady, !WordList.shared.words.isEmpty else { return }
        switch SpeakerModel.shared.state {
        case .downloading, .preparing, .waiting: return // one download at a time
        case .ready, .failed: break
        }
        retryTask?.cancel()
        retryTask = nil
        state = .downloading(fraction: fraction)
        task = Task {
            do {
                try await ParakeetEngine.downloadWordSpotter { f, preparing in
                    Task { @MainActor in WordModel.shared.progress(f, preparing: preparing) }
                }
                UserDefaults.standard.set(true, forKey: Self.preparedKey)
                task = nil
                state = .ready
            } catch {
                task = nil
                state = .failed(fraction: fraction)
                retryTask = Task {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    startIfNeeded()
                }
            }
        }
    }

    /// The model on disk didn't load: get it again.
    func broken() {
        UserDefaults.standard.removeObject(forKey: Self.preparedKey)
        state = .failed(fraction: 0)
        startIfNeeded()
    }

    private var fraction: Double {
        switch state {
        case .downloading(let f), .failed(let f): f
        case .waiting: 0
        case .preparing, .ready: 1
        }
    }

    private func progress(_ f: Double, preparing: Bool) {
        guard task != nil, state != .ready else { return }
        state = preparing ? .preparing : .downloading(fraction: f)
    }
}
