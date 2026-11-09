import AppKit
import Foundation

/// Which list a transcript line lives in: the accurate text, or the live text.
enum LineSource: Hashable {
    case checked
    case live
}

/// Edit, delete and unlock single lines, each with Undo in the bottom bar.
extension RecorderModel {
    func editLine(_ id: UUID, _ source: LineSource, start: Double, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteLine(id, source, start: start)
            return
        }
        guard var line = Self.line(id, source, start: start), line.text != trimmed else { return }
        line.text = trimmed
        line.locked = true
        guard let old = Self.replace(id, source, start: start, with: line) else { return }
        offerLineUndo("Line edited.") {
            Self.restore(id, source, start: start, old)
        }
    }

    func deleteLine(_ id: UUID, _ source: LineSource, start: Double) {
        let removed: Transcript.Line? = switch source {
        case .checked: Transcriber.shared.removeLine(id, start: start)
        case .live: LiveTranscriber.shared.removeLine(id, start: start)
        }
        guard let old = removed else { return }
        offerLineUndo("Deleted a line.") {
            if source == .live { LiveTranscriber.shared.insertLine(id, old) }
            if Self.resolved(id, source, old) == .checked { Transcriber.shared.insertLine(id, old) }
        }
    }

    /// Lets later passes change the line again.
    func unlockLine(_ id: UUID, _ source: LineSource, start: Double) {
        guard var line = Self.line(id, source, start: start), line.isLocked else { return }
        line.locked = nil
        Self.replace(id, source, start: start, with: line)
    }

    func copyLines(_ info: RecordingInfo, _ lines: [Transcript.Line]) {
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.text(lines, info: info, markdown: false), forType: .string)
        flash(lines.count == 1 ? "Copied the line." : "Copied \(lines.count) lines.")
    }

    private static func line(_ id: UUID, _ source: LineSource, start: Double) -> Transcript.Line? {
        let lines = switch source {
        case .checked: Transcriber.shared.transcripts[id]?.lines ?? []
        case .live: LiveTranscriber.shared.lines(id)
        }
        return lines.first { $0.start == start }
    }

    /// A live line the accurate pass has reached since: it lives in the
    /// checked text now (locked, if Ryan edited it).
    private static func resolved(_ id: UUID, _ source: LineSource, _ line: Transcript.Line) -> LineSource {
        guard source == .live else { return .checked }
        let done = Transcriber.shared.transcripts[id]?.doneUpTo ?? 0
        return line.middle < done ? .checked : .live
    }

    /// Undo of an edit: put the old line back, wherever the line lives now.
    private static func restore(_ id: UUID, _ source: LineSource, start: Double, _ old: Transcript.Line) {
        if source == .live { LiveTranscriber.shared.replaceLine(id, start: start, with: old) }
        guard resolved(id, source, old) == .checked else { return }
        if Transcriber.shared.replaceLine(id, start: start, with: old) == nil, source == .live {
            Transcriber.shared.insertLine(id, old)
        }
    }

    @discardableResult
    private static func replace(_ id: UUID, _ source: LineSource, start: Double, with line: Transcript.Line) -> Transcript.Line? {
        switch source {
        case .checked: Transcriber.shared.replaceLine(id, start: start, with: line)
        case .live: LiveTranscriber.shared.replaceLine(id, start: start, with: line)
        }
    }
}
