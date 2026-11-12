import Foundation

/// A note Ryan typed on a line, for what the mic can't hear ("Mr. Yurt wrote
/// the essay question on the board"). Saved like markers: as a time (the
/// line's start, seconds into the audio) in recording.json, not on the line,
/// so it stays put when lines change (Transcribe again, Find speakers).
struct LineNote: Codable, Hashable {
    var time: Double
    var text: String
}

/// Notes on lines (Ryan's ask, 2026-11-12; mockup docs/design/Notes.html).
/// One note per line, shown under it with a pencil. Copies, exports and the
/// Claude connector put "(Note: ...)" under the line.
enum Notes {
    /// The note for each line, by the line's start. A note belongs to the
    /// last line starting at or before its time (same rule as markers). If
    /// two end up on one line after lines changed, they're joined.
    static func byLine(_ lines: [Transcript.Line], _ notes: [LineNote]?) -> [Double: String] {
        guard let notes, !notes.isEmpty, !lines.isEmpty else { return [:] }
        var out: [Double: String] = [:]
        for note in notes.sorted(by: { $0.time < $1.time }) {
            let start = Markers.line(at: note.time, in: lines).start
            out[start] = out[start].map { $0 + " " + note.text } ?? note.text
        }
        return out
    }
}

extension RecorderModel {
    /// Asks the transcript on screen to start typing a note on a line.
    struct NoteRequest: Equatable {
        var id: UUID
        var start: Double
        var tick: Int
    }

    /// Sets, changes or (empty text) deletes the note on a line, with Undo.
    func setNote(_ id: UUID, line: Transcript.Line, text: String) {
        guard let i = recordingIndex(id), let info = info(id) else { return }
        let lines = shownLines(id).map(\.line)
        let old = info.notes ?? []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = Notes.byLine(lines, old)[line.start]
        guard trimmed != (before ?? "") else { return }
        var kept = old.filter { lines.isEmpty || Markers.line(at: $0.time, in: lines).start != line.start }
        if !trimmed.isEmpty { kept.append(LineNote(time: line.start, text: trimmed)) }
        kept.sort { $0.time < $1.time }
        changeRecording(i) { $0.notes = kept.isEmpty ? nil : kept }
        let message = trimmed.isEmpty ? "Note deleted." : before == nil ? "Note added at \(info.timeLabel(line.start))." : "Note changed."
        offerLineUndo(message) { [weak self] in
            guard let self, let i = self.recordingIndex(id) else { return }
            self.changeRecording(i) { $0.notes = old.isEmpty ? nil : old }
        }
    }

    /// ⇧⌘N, the toolbar Note button: a note on the line being said right now
    /// (or being heard, when audio plays). Shows the transcript and starts typing.
    func requestNote() {
        guard let target = markerTarget else { return }
        let lines = shownLines(target.id).map(\.line)
        guard !lines.isEmpty else {
            flash("No words yet to put a note on.")
            return
        }
        let line = Markers.line(at: target.time, in: lines)
        selection = target.id
        MainWindow.show()
        noteRequest = NoteRequest(id: target.id, start: line.start, tick: (noteRequest?.tick ?? 0) + 1)
    }
}
