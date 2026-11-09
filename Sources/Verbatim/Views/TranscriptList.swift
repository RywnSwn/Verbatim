import AppKit
import SwiftUI

/// Transcript lines with the time in a left gutter. Checked (accurate) text is
/// in full ink; live text is a little grey, under a thin "Checked up to" line.
/// Follows new text only if you're already at the bottom; otherwise a
/// "Jump to live" button shows.
struct TranscriptList: View {
    let info: RecordingInfo
    let checked: [Transcript.Line]
    let live: [Transcript.Line]
    var volatile: String = ""
    var isLive = false

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true

    private enum Row: Identifiable {
        case line(Transcript.Line, live: Bool, index: Int)
        case checkedUpTo(Double)
        case volatile(String)

        var id: String {
            switch self {
            case .line(_, let live, let i): "\(live ? "l" : "c")\(i)"
            case .checkedUpTo: "checked"
            case .volatile: "volatile"
            }
        }
    }

    private var rows: [Row] {
        var rows = checked.enumerated().map { Row.line($0.element, live: false, index: $0.offset) }
        if !checked.isEmpty, !live.isEmpty, let last = checked.last {
            rows.append(.checkedUpTo(last.end))
        }
        rows += live.enumerated().map { Row.line($0.element, live: true, index: $0.offset) }
        let v = volatile.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { rows.append(.volatile(v)) }
        return rows
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    switch row {
                    case .line(let line, let isLiveLine, _):
                        lineView(time: info.timeLabel(line.start), text: line.text, live: isLiveLine)
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
                        lineView(time: "", text: text, live: true)
                            .opacity(0.6)
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
            if isLive, atBottom { withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .bottom) } }
        }
        .onChange(of: volatile) {
            if isLive, atBottom { position.scrollTo(edge: .bottom) }
        }
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

    private func lineView(time: String, text: String, live: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(time)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(live ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.62)) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
