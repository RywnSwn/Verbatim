import Foundation

/// Turns Whisper's text for one piece of audio into transcript lines, word by
/// word, so that:
/// - the overlap at the start of the piece isn't doubled (words before the cut
///   were already done by the previous piece),
/// - lines Ryan deleted from the live text don't come back,
/// - lines Ryan edited in the live text are kept as he wrote them (locked).
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
    static func lines(
        _ segments: [WhisperSegment],
        offset: Double,
        keepFrom: Double,
        skip: [Span],
        locked: [Transcript.Line]
    ) -> [Transcript.Line] {
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
