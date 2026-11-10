import Foundation

/// Turns Whisper's text for one piece of audio into transcript lines, word by
/// word, so that:
/// - the overlap at the start of the piece isn't doubled (words before the cut
///   were already done by the previous piece),
/// - lines Ryan deleted from the live text don't come back,
/// - lines Ryan edited in the live text are kept as he wrote them (locked),
/// - live lines Whisper skipped are kept instead of vanishing.
enum ChunkMerge {
    /// A stretch of time (seconds into audio.wav) whose Whisper words are dropped.
    typealias Span = LiveText.Span

    /// Extra time around a skipped span, because Whisper and Parakeet don't time
    /// words exactly the same.
    static let spanPadding = 0.15

    /// - Parameters:
    ///   - segments: Whisper's output. Times are seconds into the piece.
    ///   - offset: where the piece starts in audio.wav (seconds).
    ///   - keepFrom: the cut where the previous piece ended. Earlier words are dropped.
    ///   - skip: deleted lines and locked lines; Whisper's words there are dropped.
    ///   - locked: Ryan's edited live lines that belong to this piece. Added as they are.
    ///   - live: Ryan's unedited live lines around this piece. Used to spot
    ///     text Whisper made up, and live lines Whisper skipped (kept as they are).
    ///   - keepTo: where this piece ends. Live lines after it belong to the next one.
    static func lines(
        _ segments: [WhisperSegment],
        offset: Double,
        keepFrom: Double,
        skip: [Span],
        locked: [Transcript.Line],
        live: [Transcript.Line] = [],
        keepTo: Double = .infinity
    ) -> [Transcript.Line] {
        let segments = cleaned(segments, offset: offset, live: live)
        let missed = skipped(live, by: segments, offset: offset, from: keepFrom, to: keepTo)
        let skip = skip + missed.map { Span(start: $0.start, end: $0.end) }
        let locked = locked + missed
        var out: [Transcript.Line] = []
        for segment in segments {
            let words: [WhisperWord] = segment.words.isEmpty
                ? [WhisperWord(text: " " + segment.text, start: segment.start, end: segment.end)]
                : segment.words
            var run: [WhisperWord] = []
            var dropped = false
            for w in words {
                let word = WhisperWord(text: w.text, start: w.start + offset, end: w.end + offset)
                if keeps(word, keepFrom: keepFrom, skip: skip) {
                    run.append(word)
                } else {
                    dropped = true
                    if let line = line(from: run) { out.append(line) }
                    run = []
                }
            }
            if !dropped, !segment.words.isEmpty, let first = run.first, let last = run.last {
                // Nothing dropped: use Whisper's own text for the segment (same words,
                // tidier spacing).
                out.append(Transcript.Line(start: first.start, end: last.end, text: segment.text))
            } else if let line = line(from: run) {
                out.append(line)
            }
        }
        out += locked
        return out.sorted { $0.start < $1.start }
    }

    /// Drops Whisper's usual mistakes, in order:
    /// - one phrase over and over ("I'm not a vampire. I'm not a vampire. ..."),
    /// - starting by saying the end of the segment before again (those words go),
    /// - a segment that mostly repeats the two before it,
    /// - a segment with almost nothing in common with the live text said around
    ///   the same time (made up on unclear audio: "I think that's a great way to
    ///   get to know what he's doing").
    static func cleaned(_ segments: [WhisperSegment], offset: Double, live: [Transcript.Line]) -> [WhisperSegment] {
        var kept: [WhisperSegment] = []
        for original in segments {
            var segment = original
            var words = TextCheck.words(segment.text)
            if TextCheck.loops(words) { continue }
            if let previous = kept.last {
                let n = TextCheck.overlap(TextCheck.words(previous.text), words)
                if n >= 4 {
                    if n >= words.count - 1 { continue }
                    guard let trimmed = dropFirst(n, of: segment) else { continue }
                    segment = trimmed
                    words = TextCheck.words(segment.text)
                }
            }
            if words.count >= 4 {
                let recent = TextCheck.pairs(kept.suffix(2).flatMap { TextCheck.words($0.text) })
                if TextCheck.found(words, in: recent) >= 0.7 { continue }
            }
            if words.count >= 5 {
                let s = segment.start + offset, e = segment.end + offset
                let near = live.filter { $0.end >= s - 10 && $0.start <= e + 10 }.flatMap { TextCheck.words($0.text) }
                if near.count >= 5, TextCheck.found(words, in: TextCheck.pairs(near)) < 0.2 { continue }
            }
            kept.append(segment)
        }
        return kept
    }

    /// The segment without its first `n` words. nil if it has no word times
    /// (then it can't be cut, and stays whole).
    private static func dropFirst(_ n: Int, of segment: WhisperSegment) -> WhisperSegment? {
        guard !segment.words.isEmpty else { return segment }
        var count = 0
        var rest = segment.words[...]
        while count < n, let w = rest.first {
            count += TextCheck.words(w.text).count
            rest = rest.dropFirst()
        }
        guard let first = rest.first, let last = rest.last else { return nil }
        let text = rest.map(\.text).joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return WhisperSegment(start: first.start, end: last.end, text: text, words: Array(rest))
    }

    /// Whisper sometimes skips a stretch of speech (it stops early in a 30 s
    /// window, or decides it was silence). A live line whose word pairs are
    /// mostly missing from Whisper's text around it is such a stretch: keep the
    /// live line. Compared by text, not by time, because Whisper's and the live
    /// engine's word times can be a few seconds apart (the time check made
    /// doubled lines).
    static let missedBelow = 0.4

    static func skipped(_ live: [Transcript.Line], by segments: [WhisperSegment], offset: Double, from: Double, to: Double) -> [Transcript.Line] {
        live.filter { line in
            guard !line.isLocked, line.middle >= from, line.middle < to else { return false }
            let words = TextCheck.words(line.text)
            guard words.count >= 4 else { return false }
            let near = segments
                .filter { $0.end + offset >= line.start - 20 && $0.start + offset <= line.end + 20 }
                .flatMap { TextCheck.words($0.text) }
            return TextCheck.found(words, in: TextCheck.pairs(near)) < missedBelow
        }
    }

    private static func keeps(_ word: WhisperWord, keepFrom: Double, skip: [Span]) -> Bool {
        let mid = (word.start + word.end) / 2
        if mid < keepFrom { return false }
        return !skip.contains { mid >= $0.start - spanPadding && mid <= $0.end + spanPadding }
    }

    private static func line(from words: [WhisperWord]) -> Transcript.Line? {
        guard let first = words.first, let last = words.last else { return nil }
        let text = words.map(\.text).joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A lone bit of punctuation left over after dropping words isn't a line.
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return Transcript.Line(start: first.start, end: last.end, text: text)
    }
}

extension Transcript.Line {
    /// Middle of the line. Decides which side of a cut a line belongs to.
    var middle: Double { (start + end) / 2 }
}

extension LiveText {
    /// Live lines the accurate text hasn't replaced yet.
    func unchecked(after doneUpTo: Double) -> [Transcript.Line] {
        lines.filter { $0.middle >= doneUpTo }
    }
}

/// Compares bits of text by word pairs ("the king", "king is"), ignoring
/// case and punctuation. Pairs, not single words, so common words like "the"
/// don't make different text look the same.
enum TextCheck {
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}") }
            .map { $0.filter { $0 != "'" && $0 != "\u{2019}" } }
            .filter { !$0.isEmpty }
    }

    static func pairs(_ words: [String]) -> Set<String> {
        guard words.count > 1 else { return Set(words) }
        return Set(zip(words, words.dropFirst()).map { $0 + " " + $1 })
    }

    /// Share of the word pairs in `words` that are in `other` (0 to 1).
    static func found(_ words: [String], in other: Set<String>) -> Double {
        let p = pairs(words)
        guard !p.isEmpty else { return 1 }
        return Double(p.filter(other.contains).count) / Double(p.count)
    }

    /// Says the same few words over and over.
    static func loops(_ words: [String]) -> Bool {
        guard words.count >= 12 else { return false }
        return Double(pairs(words).count) / Double(words.count - 1) < 0.5
    }

    /// How many words at the start of `next` repeat the end of `previous`.
    static func overlap(_ previous: [String], _ next: [String]) -> Int {
        let most = min(previous.count, next.count, 40)
        guard most > 0 else { return 0 }
        for k in stride(from: most, through: 1, by: -1) where Array(previous.suffix(k)) == Array(next.prefix(k)) {
            return k
        }
        return 0
    }
}
