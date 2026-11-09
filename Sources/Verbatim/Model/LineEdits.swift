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
            Self.replace(id, source, start: start, with: old)
        }
    }

    func deleteLine(_ id: UUID, _ source: LineSource, start: Double) {
        let removed: Transcript.Line? = switch source {
        case .checked: Transcriber.shared.removeLine(id, start: start)
        case .live: LiveTranscriber.shared.removeLine(id, start: start)
        }
        guard let old = removed else { return }
        offerLineUndo("Deleted a line.") {
            switch source {
            case .checked: Transcriber.shared.insertLine(id, old)
            case .live: LiveTranscriber.shared.insertLine(id, old)
            }
        }
    }

    /// Lets later passes change the line again.
    func unlockLine(_ id: UUID, _ source: LineSource, start: Double) {
        guard var line = Self.line(id, source, start: start), line.isLocked else { return }
        line.locked = nil
        Self.replace(id, source, start: start, with: line)
    }

    func copyLines(_ lines: [Transcript.Line]) {
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
        flash(lines.count == 1 ? "Copied the line." : "Copied \(lines.count) lines.")
    }

    private static func line(_ id: UUID, _ source: LineSource, start: Double) -> Transcript.Line? {
        let lines = switch source {
        case .checked: Transcriber.shared.transcripts[id]?.lines ?? []
        case .live: LiveTranscriber.shared.lines(id)
        }
        return lines.first { $0.start == start }
    }

    @discardableResult
    private static func replace(_ id: UUID, _ source: LineSource, start: Double, with line: Transcript.Line) -> Transcript.Line? {
        switch source {
        case .checked: Transcriber.shared.replaceLine(id, start: start, with: line)
        case .live: LiveTranscriber.shared.replaceLine(id, start: start, with: line)
        }
    }
}
