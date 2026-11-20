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
        offerLineUndo("Line edited.", in: id) { [weak self] in
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
        offerLineUndo(text, in: offer.recordingID) {
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

    /// Right-click > Add line below, once something was typed. Locked like
    /// an edit (later passes leave it alone), with the speaker Ryan left on
    /// it. Nothing typed: nothing added.
    func addLine(_ id: UUID, below: Double, text: String, speaker: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let live = LiveTranscriber.shared
        guard let at = Self.newLineTimes(live.lines(id), below: below) else { return }
        var line = Transcript.Line(start: at.start, end: at.end, text: trimmed, locked: true)
        line.speaker = speaker
        live.insertLine(id, line)
        offerLineUndo("Added a line.", in: id) {
            live.discardLine(id, start: at.start)
        }
    }

    /// Where a line added under `below` goes: in the gap before the next
    /// line, so the order and the times stay right. At the very end (also
    /// while recording) just after the last line, before any new words.
    static func newLineTimes(_ lines: [Transcript.Line], below: Double) -> (start: Double, end: Double)? {
        guard let i = lines.firstIndex(where: { $0.start == below }) else { return nil }
        let above = lines[i]
        let low = max(above.end, above.start)
        guard i + 1 < lines.count, lines[i + 1].start > above.start else {
            return (low + 0.01, low + 0.02)
        }
        let next = lines[i + 1].start
        if low < next { return ((low + next) / 2, next) }
        let start = (above.start + next) / 2 // lines overlap: halfway between their starts
        return (start, start)
    }

    /// The line's flags and note go with it, in the same Undo (B4: they used
    /// to move onto the line above, and notes got joined there).
    func deleteLine(_ id: UUID, _ source: LineSource, start: Double) {
        let lines = shownLines(id).map(\.line)
        let oldMarkers = info(id)?.markers ?? []
        let oldNotes = info(id)?.notes ?? []
        let onLine: (Double) -> Bool = { !lines.isEmpty && Markers.line(at: $0, in: lines).start == start }
        let removed: Transcript.Line? = switch source {
        case .checked: Transcriber.shared.removeLine(id, start: start)
        case .live: LiveTranscriber.shared.removeLine(id, start: start)
        }
        guard let old = removed else { return }
        let keptMarkers = oldMarkers.filter { !onLine($0) }
        let keptNotes = oldNotes.filter { !onLine($0.time) }
        let tookMarker = keptMarkers.count != oldMarkers.count
        let tookNote = keptNotes.count != oldNotes.count
        if tookMarker { setMarkers(id, keptMarkers) }
        if tookNote, let i = recordingIndex(id) {
            changeRecording(i) { $0.notes = keptNotes.isEmpty ? nil : keptNotes }
        }
        let extra = tookMarker && tookNote ? " Its marker and note went with it."
            : tookMarker ? " Its marker went with it." : tookNote ? " Its note went with it." : ""
        offerLineUndo("Deleted a line.\(extra)", in: id) { [weak self] in
            if source == .live { LiveTranscriber.shared.insertLine(id, old) }
            if Self.resolved(id, source, old) == .checked { Transcriber.shared.insertLine(id, old) }
            // Only what went with the line comes back: markers and notes
            // added since then stay.
            guard let self else { return }
            if tookMarker {
                let gone = oldMarkers.filter { onLine($0) }
                self.setMarkers(id, self.markers(id) + gone)
            }
            if tookNote, let i = self.recordingIndex(id) {
                let gone = oldNotes.filter { onLine($0.time) }
                let now = self.info(id)?.notes ?? []
                self.changeRecording(i) { $0.notes = (now + gone).sorted { $0.time < $1.time } }
            }
        }
    }

    /// More > Transcribe again. One click, but on ⌘Z and the Undo link, which
    /// put the text back as it was, names included (item 2: speaker names
    /// and picks were lost for good).
    func transcribeAgain(_ id: UUID) {
        redoWithUndo(id, "Transcribing again.") { Transcriber.shared.redo(id) }
    }

    /// More > Find speakers again, with the same Undo.
    func findSpeakersAgain(_ id: UUID) {
        redoWithUndo(id, "Finding speakers again.") { Transcriber.shared.findSpeakers(id) }
    }

    private func redoWithUndo(_ id: UUID, _ text: String, start: () -> Void) {
        let old = LiveTranscriber.shared.texts[id]
        // An old recording may still have its Whisper transcript (before step
        // 5c). Transcribe again deletes it, so Undo has to put it back too.
        let oldWhisper = Transcriber.shared.transcripts[id]
        start()
        guard old != nil || oldWhisper != nil else { return }
        offerLineUndo("\(text) Undo puts the text back as it was.", in: id) {
            let t = Transcriber.shared
            t.cancel(id)
            // The pass writes its last words as it stops: put the old text
            // back after that, or they'd land in it.
            Task { @MainActor in
                while t.active?.id == id { try? await Task.sleep(for: .milliseconds(50)) }
                // No live text before: an empty one (no pass), so the old
                // transcript shows by itself and nothing starts again.
                LiveTranscriber.shared.setText(old ?? LiveText(), for: id)
                if let oldWhisper, t.transcripts[id] == nil { t.putBackOld(oldWhisper, id) }
            }
        }
    }

    /// Why Transcribe again can't be used right now, nil if it can (item 15).
    func transcribeAgainBlocker(_ info: RecordingInfo) -> String? {
        let t = Transcriber.shared
        if !info.hasAudio { return "the audio was deleted" }
        if t.isGrowing(info.id) { return "still recording" }
        if t.importing.contains(info.id) { return "still importing" }
        if t.active?.id == info.id { return "transcribing now" }
        return nil
    }

    /// Why Find speakers again can't be used right now, nil if it can.
    func findSpeakersBlocker(_ info: RecordingInfo, hasLines: Bool) -> String? {
        let t = Transcriber.shared
        if !info.hasAudio { return "the audio was deleted" }
        if !SpeakerModel.shared.isReady { return "speaker labels are still downloading" }
        if !hasLines { return "no text yet" }
        if t.isGrowing(info.id) { return "still recording" }
        if t.isFindingSpeakers(info.id) || t.active?.id == info.id || t.isUnfinished(info.id) { return "busy with this one now" }
        return nil
    }

    /// Lets later passes change the line again.
    func unlockLine(_ id: UUID, _ source: LineSource, start: Double) {
        guard var line = Self.line(id, source, start: start), line.isLocked else { return }
        let old = line
        line.locked = nil
        Self.replace(id, source, start: start, with: line)
        // Item 5: it unlocked silently, with no way back.
        offerLineUndo("Line unlocked. Transcribe again may change it now.", in: id) {
            Self.replace(id, source, start: start, with: old)
        }
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
