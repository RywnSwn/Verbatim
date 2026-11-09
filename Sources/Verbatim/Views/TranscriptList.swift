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

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    @State private var editing: EditKey?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

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
            case .line(let l, let s): "\(s == .live ? "l" : "c")\(l.start)"
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
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    switch row {
                    case .line(let line, let source):
                        lineRow(line, source)
                    case .checkedUpTo(let seconds):
                        HStack(spacing: 10) {
                            Text("Checked up to \(info.timeLabel(seconds))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            VStack { Divider() }
                        }
                        .padding(.leading, 70)
                        .padding(.vertical, 4)
                    case .volatile(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Color.clear.frame(width: 52, height: 1)
                            Text(text)
                                .font(.system(size: 15))
                                .lineSpacing(3)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
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
        .overlay(alignment: .bottom) {
            if isLive, !atBottom {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) }
                } label: {
                    Label("Jump to live", systemImage: "arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
    }

    /// Don't scroll away from a line you're editing.
    private var followsLive: Bool { isLive && atBottom && editing == nil }

    private func lineRow(_ line: Transcript.Line, _ source: LineSource) -> some View {
        let key = EditKey(source: source, start: line.start)
        let isEditing = editing == key
        let grey = source == .live && !line.isLocked
        return HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(info.timeLabel(line.start))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            if isEditing {
                TextField("Line", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .focused($fieldFocused)
                    .onSubmit { save() }
                    .onExitCommand { cancel() }
                    .padding(.vertical, 2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.accentColor).frame(height: 1).offset(y: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(line.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(grey ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.62)) : AnyShapeStyle(.primary))
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
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { begin(line, source) } }
        .contextMenu {
            Button("Copy this line") { model.copyLines([line]) }
            Button("Copy from here down") { model.copyLines(linesFrom(line, source)) }
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
    /// Clock time (10:42) for recordings, time since start (37:12) for imported files.
    func timeLabel(_ seconds: Double) -> String {
        if importedFrom != nil {
            let s = Int(seconds)
            return s >= 3600
                ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
        return wallTime(atSecond: seconds).formatted(.dateTime.hour().minute())
    }
}

/// The Copy all button: copies, then says "Copied 58 lines" for a moment.
struct CopyAllButton: View {
    let lines: [Transcript.Line]
    @State private var copiedLabel: String?

    var body: some View {
        Button(copiedLabel ?? "Copy all") { copy() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(lines.isEmpty)
            .help(lines.isEmpty ? "Nothing to copy yet" : "Copy the whole transcript (⇧⌘C)")
    }

    private func copy() {
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
        let label = "Copied \(lines.count) lines"
        copiedLabel = label
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedLabel == label { copiedLabel = nil }
        }
    }
}
