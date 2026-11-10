import Foundation

/// Markers (step 7b): flag a moment that matters ("write this down").
/// Saved as times (seconds into the audio) in recording.json, not on lines,
/// so they stay put when lines change (Transcribe again, Find speakers).
/// A line is marked when a marker falls between its start and the next
/// line's start. Shown as a flag by the time; copies and exports put "⚑ " in
/// front; "Copy marked parts only" copies just those lines.
enum Markers {
    /// You press ⌘D just after hearing it, so the mark goes a bit earlier.
    static let reactionSeconds = 1.5

    /// Starts of the marked lines. `lines` in order, all of the transcript.
    static func markedStarts(_ lines: [Transcript.Line], _ markers: [Double]?) -> Set<Double> {
        guard let markers, !markers.isEmpty, !lines.isEmpty else { return [] }
        var out = Set<Double>()
        for m in markers { out.insert(line(at: m, in: lines).start) }
        return out
    }

    /// The line a moment belongs to: the last one starting at or before it
    /// (or the first line, for a moment before any text).
    static func line(at time: Double, in lines: [Transcript.Line]) -> Transcript.Line {
        lines.last { $0.start <= time } ?? lines[0]
    }
}

extension RecorderModel {
    func markers(_ id: UUID) -> [Double] { info(id)?.markers ?? [] }

    /// Where ⌘D marks: the recording in progress (a moment ago), or where the
    /// player is on the recording on screen. nil = nothing to mark.
    var markerTarget: (id: UUID, time: Double)? {
        if isBusy, let id = currentID {
            return (id, max(0, elapsed - Markers.reactionSeconds))
        }
        if let id = shownID, Playback.shared.isShowing(id) {
            return (id, max(0, Playback.shared.time - Markers.reactionSeconds))
        }
        return nil
    }

    /// ⌘D, the toolbar Marker button, the menu.
    func addMarker() {
        guard let target = markerTarget, let info = info(target.id) else { return }
        addMarker(target.id, at: target.time, label: info.timeLabel(target.time))
    }

    /// Right-click a line > Add marker here.
    func addMarker(_ id: UUID, line: Transcript.Line) {
        guard let info = info(id) else { return }
        addMarker(id, at: line.start, label: info.timeLabel(line.start))
    }

    private func addMarker(_ id: UUID, at time: Double, label: String) {
        let old = markers(id)
        setMarkers(id, old + [(time * 100).rounded() / 100])
        offerLineUndo("Marker added at \(label).") { [weak self] in
            self?.setMarkers(id, old)
        }
    }

    /// Right-click a marked line > Remove marker. Takes away every marker on it.
    func removeMarker(_ id: UUID, line: Transcript.Line) {
        let lines = shownLines(id).map(\.line)
        guard !lines.isEmpty else { return }
        let old = markers(id)
        let kept = old.filter { Markers.line(at: $0, in: lines).start != line.start }
        guard kept.count != old.count else { return }
        setMarkers(id, kept)
        offerLineUndo("Marker removed.") { [weak self] in
            self?.setMarkers(id, old)
        }
    }
}
