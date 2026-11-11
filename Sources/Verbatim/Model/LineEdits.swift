import AppKit
import Foundation

/// Which list a transcript line lives in: an old Whisper transcript, or the live text (the transcript since step 5c).
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
        line.words = nil // word times no longer match; the player estimates
        guard let old = Self.replace(id, source, start: start, with: line) else { return }
        offerLineUndo("Line edited.") { [weak self] in
            Self.restore(id, source, start: start, old)
            if self?.fixOffer?.start == start { self?.fixOffer = nil }
        }
        // Step 8: "Fix 'Father Nazi' to 'Anansi' in future transcripts too?"
        if let fix = Fixes.offer(old: old.text, new: trimmed), WordList.shared.fix(for: fix.from)?.to != fix.to {
            fixOffer = FixOffer(recordingID: id, start: start, fix: fix)
        } else {
            fixOffer = nil
        }
    }

    // MARK: - Fixes (step 8)

    /// Remember: the fix becomes a rule for new text, fixes the rest of this
    /// transcript, and a name goes in the word list. One Undo takes it all back.
    func rememberFix() {
        guard let offer = fixOffer else { return }
        fixOffer = nil
        let list = WordList.shared
        let replaced = list.addFix(offer.fix)
        var addedWord: String?
        if Fixes.looksLikeName(offer.fix.to), case .added(let w) = list.addWord(offer.fix.to) { addedWord = w }
        let changed = LiveTranscriber.shared.applyRule(offer.fix, to: offer.recordingID)

        var text = "Remembered."
        if !changed.isEmpty {
            text += changed.count == 1 ? " Fixed it in 1 more line." : " Fixed it in \(changed.count) more lines."
        }
        if let addedWord { text += " \(addedWord) is in the word list too." }
        offerLineUndo(text) {
            LiveTranscriber.shared.undoRule(changed, in: offer.recordingID)
            if let addedWord { list.removeWord(addedWord) }
            if let i = list.fixes.firstIndex(where: { $0.id == offer.fix.id }) {
                let current = list.fixes[i]
                list.removeFix(current)
                if let replaced { list.insertFix(replaced, at: i) }
            }
        }
    }

    func dismissFix() { fixOffer = nil }

    /// Right-click > Add a word to word list.
    func addToWordList(_ raw: String) {
        switch WordList.shared.addWord(raw) {
        case .added(let w):
            flash(isBusy ? "Added \(w) to the word list. Used after Pause or in the next recording." : "Added \(w) to the word list.")
        case .alreadyThere(let w):
            flash("\(w) is already in the word list.")
        case .problem(let p):
            flash(p)
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

    /// (Before step 5c) a live line the Whisper pass had reached: it lives in the
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
