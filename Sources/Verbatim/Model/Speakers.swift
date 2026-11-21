import Foundation
import Observation

/// Speaker labels (step 7). The speaker model only tells voices apart, so
/// voices show as "Speaker 1", "Speaker 2"... (1 = first heard; numbers
/// never change, see `LiveText.voiceNumbers`), for a
/// class, a video, anything. Ryan renames a voice once ("Mr. Yurt") and every
/// line in it changes. Names he typed before are offered in every recording,
/// so next class it's two clicks.
///
/// What a line shows, first match wins:
/// 1. `Line.speaker`: Ryan picked it for this line.
/// 2. `LiveText.voiceNames[voice]`: Ryan named the whole voice.
/// 3. "Speaker N".
/// Both 1 and 2 hold a name, or "#v5" = "same as voice 5" (picking another
/// speaker from the menu). No voice (old recordings, no speaker model yet):
/// no label.
enum Speakers {
    /// Names Ryan typed, newest first, offered in every recording.
    static let recentKey = "recentSpeakerNames"

    static var recentNames: [String] { SpeakerNames.shared.recent }

    static func remember(_ name: String) {
        var names = recentNames.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        names.insert(name, at: 0)
        SpeakerNames.shared.set(Array(names.prefix(8)))
    }

    /// Stops offering a name (Ryan: one-time names piled up with no way to
    /// remove them). Transcripts that use it keep it. Returns where it was,
    /// for Undo.
    @discardableResult
    static func forget(_ name: String) -> Int? {
        var names = recentNames
        guard let i = names.firstIndex(of: name) else { return nil }
        names.remove(at: i)
        SpeakerNames.shared.set(names)
        return i
    }

    static func restore(_ name: String, at i: Int) {
        var names = recentNames.filter { $0 != name }
        names.insert(name, at: min(i, names.count))
        SpeakerNames.shared.set(Array(names.prefix(8)))
    }

    static func token(_ voice: Int) -> String { "#v\(voice)" }

    static func voice(of token: String) -> Int? {
        token.hasPrefix("#v") ? Int(token.dropFirst(2)) : nil
    }

    /// "Speaker N" numbers: the ones already given stay, then voices with no
    /// name and no number get the next ones, in the order first heard.
    static func numbers(lines: [Transcript.Line], names: [String: String]?,
                        given: [String: Int]?) -> [String: Int] {
        var out = given ?? [:]
        var next = (out.values.max() ?? 0) + 1
        var seen = Set<Int>()
        for l in lines {
            guard let v = l.voice, seen.insert(v).inserted else { continue }
            let key = "\(v)"
            if out[key] == nil, names?[key] == nil {
                out[key] = next
                next += 1
            }
        }
        return out
    }

    /// Works out labels for one recording's lines.
    struct Labeler {
        var names: [String: String]
        /// Voices in the order first heard.
        var ranked: [Int]
        /// "Speaker N" number of each voice (see `Speakers.numbers`).
        var numbers: [String: Int]

        init(lines: [Transcript.Line], names: [String: String]?, numbers given: [String: Int]? = nil) {
            self.names = names ?? [:]
            var seen = Set<Int>()
            ranked = lines.compactMap(\.voice).filter { seen.insert($0).inserted }
            numbers = Speakers.numbers(lines: lines, names: names, given: given)
        }

        init(_ t: LiveText?) {
            self.init(lines: t?.lines ?? [], names: t?.voiceNames, numbers: t?.voiceNumbers)
        }

        /// The voice whose name this voice shows ("#v5" chains followed).
        func root(_ voice: Int) -> Int {
            var v = voice
            for _ in 0..<5 {
                guard let n = names["\(v)"], let other = Speakers.voice(of: n), other != v else { return v }
                v = other
            }
            return v
        }

        /// The voice whose name a line shows. nil: no voice, or a name Ryan
        /// typed for just this line.
        func root(of line: Transcript.Line) -> Int? {
            guard let c = choice(line), let v = Speakers.voice(of: c) else { return nil }
            return root(v)
        }

        /// How many lines show this voice's name (renaming it changes them all).
        func count(_ voice: Int, in lines: [Transcript.Line]) -> Int {
            let r = root(voice)
            return lines.filter { root(of: $0) == r }.count
        }

        /// The name a voice shows.
        func name(voice: Int) -> String {
            let r = root(voice)
            if let n = names["\(r)"], Speakers.voice(of: n) == nil { return n }
            return "Speaker \(numbers["\(r)"] ?? numbers.count + 1)"
        }

        /// What's picked for the line: a name, "#v5", or nil (no label).
        func choice(_ line: Transcript.Line) -> String? {
            line.speaker ?? line.voice.map(Speakers.token)
        }

        func display(_ choice: String) -> String {
            Speakers.voice(of: choice).map { name(voice: $0) } ?? choice
        }

        func name(_ line: Transcript.Line) -> String? { choice(line).map(display) }

        /// Everyone to offer in the menu: this recording's speakers, then names
        /// Ryan used in other recordings. (choice, name), no name twice.
        func options(_ lines: [Transcript.Line]) -> [SpeakerOption] {
            var out: [SpeakerOption] = []
            var seen = Set<String>()
            func add(_ choice: String) {
                let n = display(choice)
                if seen.insert(n.lowercased()).inserted { out.append(SpeakerOption(choice: choice, name: n)) }
            }
            for v in ranked { add(Speakers.token(v)) }
            for l in lines { if let s = l.speaker { add(s) } }
            for n in Speakers.recentNames { add(n) }
            return out
        }
    }

    struct SpeakerOption: Hashable {
        var choice: String
        var name: String
    }

    @MainActor
    static func labeler(_ id: UUID) -> Labeler {
        let t = LiveTranscriber.shared.texts[id]
        return Labeler(t)
    }

    // MARK: - Going over the whole file

    /// Gives lines voices from the speaker model's pass over the whole file.
    /// A line where the voice changes partway is split at the word where it
    /// changes (needs word times; edited lines keep one voice, the one heard
    /// most). A voice change of a single word isn't trusted.
    static func relabel(_ lines: [Transcript.Line], frames: VoiceFrames, base: Int) -> [Transcript.Line] {
        var out: [Transcript.Line] = []
        for line in lines {
            let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !line.isLocked, let starts = line.words, starts.count == words.count, words.count > 1 else {
                var l = line
                l.voice = frames.voice(line.start, line.end).map { $0 + base }
                out.append(l)
                continue
            }
            // Voice of each word.
            let voices: [Int?] = words.indices.map { i in
                let end = i + 1 < starts.count ? starts[i + 1] : line.end
                return frames.voice(starts[i], max(end, starts[i] + 0.05)).map { $0 + base }
            }
            // Runs of the same voice. Words with no voice join the run before.
            var runs: [(voice: Int?, from: Int, to: Int)] = []
            for (i, v) in voices.enumerated() {
                if let last = runs.last, v == nil || last.voice == nil || last.voice == v {
                    runs[runs.count - 1].to = i + 1
                    if runs[runs.count - 1].voice == nil { runs[runs.count - 1].voice = v }
                } else {
                    runs.append((v, i, i + 1))
                }
            }
            // One-word runs go into the run before (or after, if first).
            var k = 0
            while runs.count > 1, k < runs.count {
                if runs[k].to - runs[k].from == 1 {
                    if k > 0 {
                        runs[k - 1].to = runs[k].to
                    } else {
                        runs[1].from = runs[0].from
                    }
                    runs.remove(at: k)
                    // Neighbours may now have the same voice: join them.
                    var j = 1
                    while j < runs.count {
                        if runs[j].voice == runs[j - 1].voice {
                            runs[j - 1].to = runs[j].to
                            runs.remove(at: j)
                        } else { j += 1 }
                    }
                    k = 0
                } else {
                    k += 1
                }
            }
            for (n, run) in runs.enumerated() {
                var l = line
                l.text = words[run.from..<run.to].joined(separator: " ")
                l.words = Array(starts[run.from..<run.to])
                l.start = n == 0 ? line.start : starts[run.from]
                l.end = run.to < starts.count ? starts[run.to] : line.end
                l.voice = run.voice
                if n > 0 { l.speaker = nil }
                out.append(l)
            }
        }
        return out
    }
}

// MARK: - Fixing labels (click a label)

extension RecorderModel {
    /// "Just This Line": Ryan picked who said this one line. Nothing else changes.
    func setSpeaker(_ id: UUID, start: Double, to choice: String) {
        let live = LiveTranscriber.shared
        guard let line = live.lines(id).first(where: { $0.start == start }) else { return }
        let before = Speakers.labeler(id)
        guard before.choice(line) != choice else { return }
        if Speakers.voice(of: choice) == nil { Speakers.remember(choice) }
        var changed = line
        // Back to its own voice: just follow the voice again.
        changed.speaker = choice == line.voice.map(Speakers.token) ? nil : choice
        live.replaceLine(id, start: start, with: changed)
        // Hunt 1 bug 1: on Undo only the pick goes back. While recording the
        // newest line keeps growing, and putting back the whole old line
        // threw away every word said since the pick.
        let oldSpeaker = line.speaker
        offerLineUndo("Just this line is now \(before.display(choice)).", in: id) {
            LiveTranscriber.shared.changeLine(id, start: start) { $0.speaker = oldSpeaker }
        }
    }

    /// Every line that shows this voice's name becomes `choice` (a name, or
    /// "#v5" to join another speaker). A typed name that another speaker in
    /// this recording already has joins that speaker, so there's one
    /// Mr. Yurt, not two. Lines Ryan set with "Just This Line" stay.
    func renameVoice(_ id: UUID, voice: Int, to typed: String) {
        let live = LiveTranscriber.shared
        let before = Speakers.labeler(id)
        let lines = live.lines(id)
        let v = before.root(voice)
        let oldName = before.name(voice: v)
        var choice = typed
        if Speakers.voice(of: choice) == nil {
            if choice == oldName { return }
            if let other = before.ranked.map({ before.root($0) }).first(where: {
                $0 != v && before.name(voice: $0).caseInsensitiveCompare(typed) == .orderedSame
            }) {
                choice = Speakers.token(other)
            }
        }
        if let target = Speakers.voice(of: choice), before.root(target) == v { return }
        if Speakers.voice(of: choice) == nil { Speakers.remember(choice) }
        let count = before.count(v, in: lines)
        let old = live.texts[id]?.voiceNames?["\(v)"]
        live.setVoiceName(id, voice: v, to: choice)
        let lineText = count == 1 ? "1 line" : "\(count) lines"
        let text = "\(oldName) is now \(before.display(choice)) (\(lineText))."
        let undoName = {
            LiveTranscriber.shared.setVoiceName(id, voice: v, to: old)
        }
        // A real name: remember the voice for next time (step 7c).
        guard Speakers.voice(of: choice) == nil, let info = info(id) else {
            offerLineUndo(text, in: id, undo: undoName)
            return
        }
        let started = Date()
        VoiceLibrary.shared.remember(name: choice, voice: v, in: info) { [weak self] saved in
            guard let self else { return }
            guard saved else { return self.offerLineUndo(text, in: id, undo: undoName) }
            self.offerLineUndo("\(text) Verbatim will know this voice next time.", in: id) {
                undoName()
                VoiceLibrary.shared.forget(named: choice, savedAfter: started)
            }
        }
    }
}

/// The names offered in the speaker menu, saved in UserDefaults. Observable,
/// so the menu and Settings > Voices update when one is forgotten.
@Observable
final class SpeakerNames {
    static let shared = SpeakerNames()

    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: Speakers.recentKey) ?? []

    func set(_ names: [String]) {
        recent = names
        UserDefaults.standard.set(names, forKey: Speakers.recentKey)
    }
}
