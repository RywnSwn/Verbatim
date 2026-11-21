import AppKit
import SwiftUI

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
    /// (or the first line, for a moment before any text). The small slack
    /// matters: markers used to be saved rounded to 0.01 s, so one on a line
    /// starting at 12.344 was saved as 12.34 and showed on the line above
    /// (Ryan, 2026-11-21). The slack puts those old ones back.
    static func line(at time: Double, in lines: [Transcript.Line]) -> Transcript.Line {
        lines.last { $0.start <= time + slack } ?? lines[0]
    }

    /// Bigger than the old rounding (0.005 s), far smaller than any gap
    /// between two lines.
    static let slack = 0.006
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

    /// Whether ⌘D has something to mark. Same answer as `markerTarget != nil`,
    /// but doesn't read the clock, so the menu bar isn't rebuilt 20 times a second.
    var canMark: Bool {
        if isBusy, currentID != nil { return true }
        if let id = shownID { return Playback.shared.isShowing(id) }
        return false
    }

    /// ⌘D, the toolbar Marker button, the menu.
    func addMarker() {
        guard let target = markerTarget, let info = info(target.id) else { return }
        addMarker(target.id, at: target.time, label: info.timeLabel(target.time))
    }

    /// Right-click a line > Add marker here.
    func addMarker(_ id: UUID, line: Transcript.Line) {
        guard let info = info(id) else { return }
        addMarker(id, at: line.start, label: info.timeLabel(line.start), exact: true)
    }

    /// `exact`: a line's own start, saved as is (rounding it could land it
    /// just before the line, on the one above). ⌘D times are rounded.
    private func addMarker(_ id: UUID, at time: Double, label: String, exact: Bool = false) {
        let old = markers(id)
        setMarkers(id, old + [exact ? time : (time * 100).rounded() / 100])
        offerLineUndo("Marker added at \(label).", in: id) { [weak self] in
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
        offerLineUndo("Marker removed.", in: id) { [weak self] in
            self?.setMarkers(id, old)
        }
    }
}

/// Tools you pick up in the toolbar (Ryan, 2026-11-20, mockup
/// docs/design/LineTools.html). The pointer turns into a flag or a pencil and
/// lines glow yellow or red under it. Marker stays on (flag several lines)
/// until Esc or the button again; Note goes down after one note, because you
/// type it right away. ⌘D still marks what's being said right now.
enum LineTool: Equatable {
    case marker, note

    var pointer: PointerStyle {
        .image(Image(nsImage: self == .marker ? Self.flagCursor : Self.pencilCursor), hotSpot: .center)
    }

    /// A round badge, so it shows on light and dark pages alike.
    private static func badge(_ symbol: String, _ colors: [NSColor]) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
    }

    private static let flagCursor = badge("flag.circle.fill", [.black, NSColor(srgbRed: 0.95, green: 0.78, blue: 0.19, alpha: 1)])
    private static let pencilCursor = badge("pencil.circle.fill", [.white, NSColor(srgbRed: 0.85, green: 0.42, blue: 0.36, alpha: 1)])
}
