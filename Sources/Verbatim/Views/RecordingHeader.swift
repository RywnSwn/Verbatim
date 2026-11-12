import SwiftUI

/// The top of every transcript (step 10): which group, a big serif title you
/// can click to rename, when it ran, who spoke, and how many markers.
/// Real facts about the class, so the page doesn't feel empty.
struct RecordingHeader: View {
    @Environment(RecorderModel.self) private var model
    let info: RecordingInfo
    let lines: [Transcript.Line]
    let isLive: Bool

    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var groups: GroupStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrow
            title
            HeaderMeta(info: info, isLive: isLive)
            if let who = speakersText {
                Text(who)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 70) // lines up with the transcript text, past the time gutter
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var eyebrow: some View {
        if let group = groups.group(info.groupID) {
            HStack(spacing: 5) {
                ItemIcon(name: group.icon, color: group.color, size: 11)
                Text(group.name)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        } else if info.importedFrom != nil {
            Text("Voice Memo")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var title: some View {
        if renaming {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .focused($focused)
                .onSubmit { finish(save: true) }
                .onExitCommand { finish(save: false) }
                .onChange(of: focused) { if !focused, renaming { finish(save: true) } }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.accent).frame(height: 1).offset(y: 3)
                }
        } else {
            Text(info.title)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.line.opacity(hovering ? 0.7 : 0))
                        .padding(.horizontal, -5)
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture {
                    draft = info.title
                    renaming = true
                    focused = true
                }
                .help("Click to rename")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Rename")
        }
    }

    private func finish(save: Bool) {
        if save { model.rename(info.id, to: draft) }
        renaming = false
    }

    /// "Mr. Yurt, Speaker 2 and Speaker 3 spoke." Most words first, up to four.
    private var speakersText: String? {
        let labels = Speakers.labeler(info.id)
        var words: [String: Int] = [:]
        for line in lines {
            guard let name = labels.name(line) else { continue }
            words[name, default: 0] += line.text.split(whereSeparator: \.isWhitespace).count
        }
        let names = words.keys.sorted { words[$0]! != words[$1]! ? words[$0]! > words[$1]! : $0 < $1 }
        guard !names.isEmpty else { return nil }
        let shown = Array(names.prefix(4))
        let rest = names.count - shown.count
        var list: String
        if rest > 0 {
            list = shown.joined(separator: ", ") + " and \(rest) more"
        } else if shown.count == 1 {
            list = shown[0]
        } else {
            list = shown.dropLast().joined(separator: ", ") + " and " + shown.last!
        }
        return list + " spoke."
    }
}

/// "Started 10:05, 12 min so far. 2 markers." Its own view, because it reads
/// the ticking clock while recording: the clock then redraws only this line.
/// (Inside RecordingHeader it made the whole header count every word of the
/// transcript 20 times a second, which got slower the longer the class ran.)
private struct HeaderMeta: View {
    @Environment(RecorderModel.self) private var model
    let info: RecordingInfo
    let isLive: Bool

    var body: some View {
        let meta = self.meta
        Text(meta)
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: meta)
    }

    /// "10:05 to 10:52, 47 min. 2 markers." Imported files have no clock time.
    private var meta: String {
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        var parts: [String] = []
        if isLive {
            let len = RecorderModel.minutesText(model.elapsed)
            parts.append("Started \(info.createdAt.formatted(t)), \(len) so far")
        } else if let name = info.importedFrom {
            parts.append("From \(name), \(RecorderModel.minutesText(info.duration))")
        } else {
            let day = info.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
            let end = info.endedAt.map { " to \($0.formatted(t))" } ?? ""
            parts.append("\(day), \(info.createdAt.formatted(t))\(end), \(RecorderModel.minutesText(info.duration))")
        }
        let markers = info.markers?.count ?? 0
        if markers > 0 { parts.append(markers == 1 ? "1 marker" : "\(markers) markers") }
        let notes = info.notes?.count ?? 0
        if notes > 0 { parts.append(notes == 1 ? "1 note" : "\(notes) notes") }
        return parts.joined(separator: ". ") + "."
    }
}
