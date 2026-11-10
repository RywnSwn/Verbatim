import AppKit
import SwiftUI

/// Transcript lines with the time in a left gutter. Checked (accurate) text is
/// in full ink; live text is a little grey, under a thin "Checked up to" line.
/// Follows new text only if you're already at the bottom; otherwise a
/// "Jump to live" button shows.
///
/// Editing: click a line (Enter saves, Esc cancels, clicking away
/// saves), or right-click for Copy / Edit / Delete. Edited lines turn full ink
/// and get a lock; later passes never change them. Every change has Undo in
/// the bottom bar.
struct TranscriptList: View {
    @Environment(RecorderModel.self) private var model
    @Environment(LiveTranscriber.self) private var liveTranscriber
    let info: RecordingInfo
    let checked: [Transcript.Line]
    let live: [Transcript.Line]
    /// Where the checked text ends (seconds into the audio), for the divider.
    var checkedUpTo: Double?
    var volatile: String = ""
    var isLive = false

    @AppStorage(TimeStyle.key) private var timeStyle: TimeStyle = .clock
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    @State private var editing: EditKey?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    /// Last time you scrolled by hand, so playing audio doesn't yank the view away.
    @State private var lastUserScroll = Date.distantPast

    private var playback: Playback { .shared }
    /// Times in the gutter play from that line (finished recordings with audio).
    private var canPlay: Bool { !isLive && info.hasAudio }

    /// The line being heard right now, while the player is open.
    private var playingRowID: String? {
        guard !isLive, playback.isShowing(info.id) else { return nil }
        let t = playback.time + 0.05
        var found: String?
        for row in rows {
            if case .line(let line, let source) = row {
                if line.start <= t { found = TranscriptRow.id(source, line.start) } else { break }
            }
        }
        return found
    }

    private struct EditKey: Hashable {
        var source: LineSource
        var start: Double
    }

    private enum Row: Identifiable {
        case line(Transcript.Line, LineSource)
        case checkedUpTo(Double)
        case volatile(String)

        var id: String {
            switch self {
            case .line(let l, let s): TranscriptRow.id(s, l.start)
            case .checkedUpTo: "checked"
            case .volatile: "volatile"
            }
        }
    }

    private var rows: [Row] {
        var rows = checked.map { Row.line($0, .checked) }
        if !checked.isEmpty, !live.isEmpty || !volatile.isEmpty, let last = checked.last {
            rows.append(.checkedUpTo(checkedUpTo ?? last.end))
        }
        rows += live.map { Row.line($0, .live) }
        let v = volatile.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { rows.append(.volatile(v)) }
        return rows
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.lineGap) {
                ForEach(rows) { row in
                    switch row {
                    case .line(let line, let source):
                        lineRow(line, source)
                    case .checkedUpTo(let seconds):
                        HStack(spacing: 10) {
                            Text("Checked up to \(info.timeLabel(seconds, style: timeStyle))")
                                .font(.system(size: 13, design: .serif).italic())
                                .foregroundStyle(.secondary)
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }
                        .padding(.leading, 70)
                        .padding(.vertical, 4)
                    case .volatile(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Color.clear.frame(width: 52, height: 1)
                            Text(text)
                                .font(Theme.transcript)
                                .lineSpacing(Theme.transcriptLineSpacing)
                                .foregroundStyle(Theme.ink.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .background(Theme.paper)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 60
        } action: { _, bottom in
            atBottom = bottom
        }
        .onChange(of: live.count + checked.count) {
            if followsLive { withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .bottom) } }
        }
        .onChange(of: volatile) {
            if followsLive { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: fieldFocused) {
            // Clicking somewhere else saves, like a text field in Notes.
            if !fieldFocused, editing != nil { save() }
        }
        .onDisappear { if editing != nil { save() } }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting || phase == .tracking || phase == .decelerating { lastUserScroll = Date() }
        }
        .onChange(of: playingRowID) { _, id in
            // Follow the audio, unless you scrolled in the last 8 seconds or are editing/searching.
            guard let id, playback.isPlaying, editing == nil, model.searchText.isEmpty,
                  Date().timeIntervalSince(lastUserScroll) > 8 else { return }
            withAnimation(.easeOut(duration: 0.3)) { position.scrollTo(id: id, anchor: .center) }
        }
        .onChange(of: model.matchJump) { jumpToMatch() }
        .onAppear { if !model.searchText.isEmpty { jumpToMatch() } }
        .overlay(alignment: .bottom) {
            if isLive, !atBottom {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) }
                } label: {
                    Label("Jump to live", systemImage: "arrow.down")
                }
                .buttonStyle(.ink)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
    }

    /// Don't scroll away from a line you're editing or a search hit.
    private var followsLive: Bool { isLive && atBottom && editing == nil && model.searchText.isEmpty }

    // MARK: - Search

    private var query: String { model.searchText.trimmingCharacters(in: .whitespaces) }

    private var matches: [SearchMatch] { model.searchMatches(info.id) }

    private var currentMatch: SearchMatch? {
        let all = matches
        guard !all.isEmpty else { return nil }
        return all[min(model.matchIndex, all.count - 1)]
    }

    private func jumpToMatch() {
        guard let match = currentMatch else { return }
        withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: match.rowID, anchor: .center) }
    }

    /// The line's text with search hits in yellow; the current hit stronger.
    private func highlighted(_ text: String, _ source: LineSource, _ start: Double) -> AttributedString {
        let ranges = RecorderModel.ranges(of: query, in: text)
        guard !ranges.isEmpty else { return AttributedString(text) }
        let current = currentMatch.flatMap { $0.source == source && $0.start == start ? $0.occurrence : nil }
        var result = AttributedString()
        var cursor = text.startIndex
        for (k, r) in ranges.enumerated() {
            result += AttributedString(String(text[cursor..<r.lowerBound]))
            var hit = AttributedString(String(text[r]))
            hit.backgroundColor = k == current ? Theme.highlightCurrent : Theme.highlight
            hit.foregroundColor = Theme.ink
            result += hit
            cursor = r.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    private func lineRow(_ line: Transcript.Line, _ source: LineSource) -> some View {
        let key = EditKey(source: source, start: line.start)
        let isEditing = editing == key
        let grey = source == .live && !line.isLocked
        let isPlaying = playingRowID == TranscriptRow.id(source, line.start)
        return HStack(alignment: .firstTextBaseline, spacing: 18) {
            timeGutter(line, isPlaying: isPlaying)
            if isEditing {
                TextField("Line", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.transcript)
                    .lineSpacing(Theme.transcriptLineSpacing)
                    .focused($fieldFocused)
                    .onSubmit { save() }
                    .onExitCommand { cancel() }
                    .padding(.vertical, 2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.accent).frame(height: 1).offset(y: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(query.isEmpty ? AttributedString(line.text) : highlighted(line.text, source, line.start))
                    .font(Theme.transcript)
                    .lineSpacing(Theme.transcriptLineSpacing)
                    .foregroundStyle(grey ? Theme.ink.opacity(0.62) : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pointerStyle(.horizontalText) // text cursor: says "you can type here"
            }
            if line.isLocked, !isEditing {
                Button {
                    model.unlockLine(info.id, source, start: line.start)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("You edited this line, so later passes won't change it. Click to unlock.")
                .accessibilityLabel("Unlock line")
            }
        }
        .background {
            if isPlaying {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.line.opacity(0.7))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { begin(line, source) } }
        .contextMenu {
            if canPlay {
                Button("Play from here") { model.playAudio(info.id, from: line.start) }
                Divider()
            }
            Button("Copy this line") { model.copyLines(info, [line]) }
            Button("Copy from here down") { model.copyLines(info, linesFrom(line, source)) }
            Divider()
            Button("Edit line") { begin(line, source) }
            Button("Delete line") { model.deleteLine(info.id, source, start: line.start) }
            if line.isLocked {
                Divider()
                Button("Unlock") { model.unlockLine(info.id, source, start: line.start) }
            }
        }
        .accessibilityAction(named: "Edit line") { begin(line, source) }
        .accessibilityAction(named: "Delete line") { model.deleteLine(info.id, source, start: line.start) }
    }

    /// The time on the left. On finished recordings it's a button: click to
    /// hear the audio from that line (the text itself still edits).
    @ViewBuilder private func timeGutter(_ line: Transcript.Line, isPlaying: Bool) -> some View {
        let label = Text(info.timeLabel(line.start, style: timeStyle))
            .font(isPlaying ? .callout.weight(.semibold) : .callout)
            .monospacedDigit()
            .foregroundStyle(isPlaying ? Theme.accent : .secondary)
            .frame(width: 52, alignment: .trailing)
        if canPlay {
            Button {
                model.playAudio(info.id, from: line.start)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Play from here")
            .accessibilityLabel("Play from \(info.timeLabel(line.start, style: timeStyle))")
        } else {
            label
        }
    }

    private func linesFrom(_ line: Transcript.Line, _ source: LineSource) -> [Transcript.Line] {
        let all = checked + live
        let index = source == .checked
            ? checked.firstIndex { $0.start == line.start }
            : live.firstIndex { $0.start == line.start }.map { $0 + checked.count }
        guard let index else { return [line] }
        return Array(all[index...])
    }

    private func begin(_ line: Transcript.Line, _ source: LineSource) {
        if editing != nil { save() }
        draft = line.text
        editing = EditKey(source: source, start: line.start)
        if source == .live { liveTranscriber.editing = (info.id, line.start) }
        Task { @MainActor in fieldFocused = true }
    }

    private func save() {
        guard let key = editing else { return }
        finish()
        model.editLine(info.id, key.source, start: key.start, text: draft)
    }

    private func cancel() {
        finish()
    }

    private func finish() {
        editing = nil
        fieldFocused = false
        liveTranscriber.editing = nil
    }
}

extension RecordingInfo {
    /// Times in the style picked in Settings.
    func timeLabel(_ seconds: Double) -> String { timeLabel(seconds, style: TimeStyle.current) }

    /// Clock time (10:42) or time since start (37:12). Imported files always
    /// use time since start: there is no clock time for them.
    func timeLabel(_ seconds: Double, style: TimeStyle) -> String {
        if importedFrom != nil || style == .sinceStart {
            let s = Int(seconds)
            return s >= 3600
                ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
        return wallTime(atSecond: seconds).formatted(.dateTime.hour().minute())
    }
}

/// The ink Copy all button with an arrow for the other copies, like the
/// layout in docs/design/Main.dc.html. After copying it says "Copied 58 lines"
/// for a moment. Shortcuts live in the Transcript menu.
struct CopyButton: View {
    @Environment(RecorderModel.self) private var model
    let id: UUID
    let hasLines: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(model.copyFeedback?.text ?? "Copy all") { model.copy(.all) }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .help(hasLines ? "Copy the whole transcript (⇧⌘C)" : "Nothing to copy yet")
            Rectangle()
                .fill(Theme.paper.opacity(0.35))
                .frame(width: 1, height: 14)
            Menu {
                Button("Copy all") { model.copy(.all) }
                Button("Copy new since last copy") { model.copy(.new) }
                Button("Copy last 10 minutes") { model.copy(.lastTenMinutes) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.paper)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 4)
            .help("More ways to copy")
            .accessibilityLabel("More ways to copy")
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(Theme.paper)
        .background(Theme.ink, in: Capsule())
        .opacity(hasLines ? 1 : 0.35)
        .disabled(!hasLines)
        .fixedSize()
    }
}

/// Export as plain text or Markdown. Never overwrites a file without asking.
struct ExportMenu: View {
    @Environment(RecorderModel.self) private var model
    let hasLines: Bool

    var body: some View {
        Menu {
            Button("Plain text (.txt)…") { model.export(.text) }
            Button("Markdown (.md)…") { model.export(.markdown) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(!hasLines)
        .help(hasLines ? "Save the transcript as a file" : "Nothing to export yet")
    }
}
