import AppKit
import SwiftUI

/// ⌘K (step 10): type what you want, like "mark", "mon" or "bigger", and press
/// Return. Actions, recordings and groups in one list. Esc or a click outside
/// closes it.
struct CommandMenuView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    struct Command: Identifiable {
        var id: String
        var section: String
        var title: String
        var detail: String? = nil
        var shortcut: String? = nil
        var icon: String
        var iconColor: IconColor = .ink
        var words = ""
        var action: () -> Void
    }

    var body: some View {
        let shown = filtered
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                TextField("Type a command or a recording…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .focused($focused)
                    .onSubmit { run(shown) }
                    .onKeyPress(.downArrow) { move(1, shown.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, shown.count); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onChange(of: query) { selected = 0 }
                Divider()
                list(shown)
                Divider()
                Text("↑ ↓ to move, Return to run, Esc to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
            }
            .frame(width: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .padding(.top, 70)
            .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
        }
        .onAppear { focused = true }
    }

    private func list(_ shown: [Command]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if shown.isEmpty {
                        Text("Nothing called \u{201C}\(query)\u{201D}. Try copy, marker, or a day like mon.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, command in
                        if i == 0 || shown[i - 1].section != command.section {
                            Text(command.section)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, i == 0 ? 4 : 10)
                                .padding(.bottom, 2)
                        }
                        row(command, isSelected: i == selected)
                            .id(command.id)
                            .onTapGesture { selected = i; run(shown) }
                            .onHover { if $0 { selected = i } }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selected) {
                if shown.indices.contains(selected) { proxy.scrollTo(shown[selected].id) }
            }
        }
    }

    private func row(_ c: Command, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.icon)
                .font(.system(size: 13))
                .foregroundStyle(c.iconColor.color)
                .frame(width: 18)
            Text(c.title).lineLimit(1)
            if let detail = c.detail, !detail.isEmpty {
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let shortcut = c.shortcut {
                Text(shortcut).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func move(_ step: Int, _ count: Int) {
        guard count > 0 else { return }
        selected = min(max(selected + step, 0), count - 1)
    }

    private func run(_ shown: [Command]) {
        guard shown.indices.contains(selected) else { return }
        let action = shown[selected].action
        close()
        action()
    }

    private func close() {
        withAnimation(.snappy(duration: 0.15)) { model.showCommandMenu = false }
    }

    // MARK: - What's in the list

    private var filtered: [Command] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let all = commands
        guard !words.isEmpty else {
            // Nothing typed: the actions, then the 6 newest recordings.
            var goCount = 0
            return all.filter { c in
                guard c.section == "Go to" else { return true }
                goCount += 1
                return goCount <= 6
            }
        }
        return all.filter { c in
            let hay = "\(c.title) \(c.detail ?? "") \(c.words)".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    private var commands: [Command] {
        var out: [Command] = []
        let busy = model.isBusy
        let paused = model.phase == .paused
        let groups = GroupStore.shared.groups

        func add(_ id: String, _ title: String, _ icon: String, shortcut: String? = nil, words: String = "", _ action: @escaping () -> Void) {
            out.append(Command(id: id, section: "Do", title: title, shortcut: shortcut, icon: icon, words: words, action: action))
        }

        if busy {
            add("stop", "Stop recording", "stop.fill", shortcut: "⌘R", words: "end finish save") { model.stop() }
            add("pause", paused ? "Resume" : "Pause", paused ? "play.fill" : "pause.fill", shortcut: "⇧⌘P", words: "pause resume break") { model.togglePause() }
        } else {
            add("start", "Start recording", "record.circle", shortcut: "⌘R", words: "record new class begin") { Task { await model.start() } }
        }
        if model.canMark {
            add("marker", "Add marker", "flag", shortcut: "⌘D", words: "mark flag important") { model.addMarker() }
        }
        let copyFrom = busy ? model.currentID : model.shownID
        if let copyFrom, !model.shownLines(copyFrom).isEmpty {
            add("copyNew", "Copy new since last copy", "doc.on.doc", shortcut: "⌥⌘C", words: "copy new latest") { model.copy(.new, from: copyFrom) }
            add("copyAll", "Copy all", "doc.on.doc", shortcut: "⇧⌘C", words: "copy everything") { model.copy(.all, from: copyFrom) }
            add("copyTen", "Copy last 10 minutes", "clock", words: "copy recent ten") { model.copy(.lastTenMinutes, from: copyFrom) }
            add("copyMarked", "Copy marked parts only", "flag", words: "copy markers flagged") { model.copy(.marked, from: copyFrom) }
        }
        if model.hasShownLines {
            add("exportText", "Export as plain text", "square.and.arrow.up", shortcut: "⇧⌘E", words: "export save file txt") { model.export(.text) }
            add("exportMd", "Export as Markdown", "square.and.arrow.up", words: "export save file md") { model.export(.markdown) }
        }
        add("mini", MiniWindow.shared.isShown ? "Hide mini window" : "Show mini window", "pip", shortcut: "⇧⌘M", words: "small float window") { MiniWindow.shared.toggle() }
        add("memo", "Transcribe a Voice Memo", "waveform.badge.plus", shortcut: "⌘O", words: "import file audio") { model.chooseFilesToImport() }
        add("newGroup", "New group", "folder.badge.plus", words: "class folder section") {
            let group = GroupStore.shared.add()
            model.renameGroupRequest = group.id
        }
        add("bigger", "Make text bigger", "textformat.size.larger", shortcut: "⌘+", words: "text size font larger zoom") { TextSize.change(by: 1) }
        add("smaller", "Make text smaller", "textformat.size.smaller", shortcut: "⌘−", words: "text size font zoom") { TextSize.change(by: -1) }
        add("settings", "Settings", "gearshape", shortcut: "⌘,", words: "settings preferences microphone mic options") { openSettings() }

        if !busy {
            for g in groups {
                out.append(Command(id: "rec-\(g.id)", section: "Record in", title: g.name, icon: g.icon ?? "folder",
                                   iconColor: g.color, words: "record start new class") {
                    Task { await model.start(in: g.id) }
                })
            }
        }

        for r in model.recordings {
            let group = GroupStore.shared.group(r.groupID)
            let day = RecorderModel.dayTitle(r.createdAt)
            out.append(Command(
                id: "go-\(r.id)", section: "Go to", title: r.title,
                detail: [group?.name, r.title.contains(day) ? nil : day].compactMap { $0 }.joined(separator: ", "),
                icon: r.icon ?? group?.icon ?? "text.alignleft",
                iconColor: r.icon != nil ? (r.iconColor ?? .ink) : (group?.color ?? .ink),
                words: r.createdAt.formatted(.dateTime.weekday(.wide).month(.wide)) + " " + (r.importedFrom ?? "")
            ) { model.selection = r.id })
        }
        return out
    }
}
