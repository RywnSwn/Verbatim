import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Step 10: like the sidebar in Claude. Groups (one per class) with an icon
/// and a + to record right in them, then Recents for everything not in a
/// group. Right-click empty space for New Group; right-click a recording to
/// move it, or drag it onto a group. Dragged out of Verbatim (to Claude,
/// Finder, Notes) a recording becomes a Markdown file of its transcript.
///
/// Design pass (2026-11-12): our own scrolling list instead of `List`, because
/// `List` always paints its own selection highlight over the rows. Each
/// recording sits on its own box (Settings > Look: soft boxes or paper
/// cards), darker under the pointer, clearly marked when open. Dragging
/// lifts the row, leaves a gap where it was, lights up the group under the
/// pointer, and shows "Moved to X. Undo" after the drop. Arrow keys, Delete
/// and right-click work like before.
struct SidebarView: View {
    @Environment(RecorderModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SidebarLook.key) private var sidebarLook: SidebarLook = .glass
    @AppStorage(RowLook.key) private var rowLook: RowLook = .soft
    @AppStorage("recentsCollapsed") private var recentsCollapsed = false
    @State private var renaming: RecordingInfo?
    @State private var newTitle = ""
    @State private var groupDraft = ""
    @State private var iconFor: UUID?
    @FocusState private var focused: Bool

    private var store: GroupStore { .shared }
    private var drag: SidebarDrag { .shared }
    private var solid: Bool { sidebarLook == .solid || reduceTransparency }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Inside the scroll area (not a top inset), so they sit below
                // the window's buttons instead of under them.
                NewRecordingButton()
                SidebarAction(title: "Add a Voice Memo", icon: "waveform.badge.plus", shortcut: "⌘O",
                              help: "Pick a Voice Memo or other recording to turn into text. Or drop one anywhere.") {
                    model.chooseFilesToImport()
                }
                RecentlyDeletedButton()

                Divider()
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)

                ForEach(store.groups) { group in
                    groupSection(group)
                }
                recentsSection
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy(duration: 0.25), value: store.groups)
            .animation(.snappy(duration: 0.25), value: model.recordings.map(\.groupID))
        }
        // Right-click on empty space. Rows and group names have their own menus.
        .contextMenu {
            Button("New Group") { newGroup() }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .onDeleteCommand {
            if let id = model.selection, model.canDelete(id) { model.delete(id) }
        }
        .background {
            if solid { Theme.sidebarSolid.ignoresSafeArea() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Right-click empty space for a new group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Solid, so recordings scrolling past don't show through the text.
            .background(solid ? AnyShapeStyle(Theme.sidebarSolid) : AnyShapeStyle(.bar))
        }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Rename") {
                if let r = renaming { model.rename(r.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Name this group", isPresented: Binding(
            get: { model.renameGroupRequest != nil },
            set: { if !$0 { model.renameGroupRequest = nil } })
        ) {
            TextField("Like English 2026", text: $groupDraft)
            Button("OK") {
                if let id = model.renameGroupRequest { store.rename(id, to: groupDraft) }
                model.renameGroupRequest = nil
            }
            Button("Cancel", role: .cancel) { model.renameGroupRequest = nil }
        } message: {
            Text("One group per class works well. Pick an icon by clicking the one next to its name.")
        }
        .onChange(of: model.renameGroupRequest) {
            if let id = model.renameGroupRequest { groupDraft = store.group(id)?.name ?? "" }
        }
    }

    /// A group: bold name with its icon and +, then its recordings indented.
    /// The whole block is the drop zone, and lights up while a recording
    /// from somewhere else is held over it.
    private func groupSection(_ group: RecordingGroup) -> some View {
        let spot = SidebarSpot.group(group.id)
        let members = model.recordings.filter { $0.groupID == group.id }
        return VStack(alignment: .leading, spacing: 3) {
            GroupHeader(group: group, isTarget: drag.target == spot)
            if !group.collapsed {
                if members.isEmpty {
                    Text(model.isBusy ? "Empty. Drag a recording here." : "Empty. Press + or drag one here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 26)
                        .padding(.bottom, 4)
                }
                ForEach(members) { info in
                    row(info)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(3)
        .background { DropHighlight(on: drag.target == spot) }
        .onDrop(of: [.verbatimRecording], delegate: SidebarDropDelegate(spot: spot, model: model, drag: drag))
    }

    private var recentsSection: some View {
        let recents = model.recordings.filter { store.group($0.groupID) == nil }
        return VStack(alignment: .leading, spacing: 3) {
            RecentsHeader(collapsed: $recentsCollapsed, isTarget: drag.target == .recents)
            if !recentsCollapsed {
                if model.recordings.isEmpty {
                    Text("Your recordings will show up here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                ForEach(recents) { info in
                    row(info)
                }
            }
        }
        .padding(3)
        .background { DropHighlight(on: drag.target == .recents) }
        .onDrop(of: [.verbatimRecording], delegate: SidebarDropDelegate(spot: .recents, model: model, drag: drag))
    }

    private func row(_ info: RecordingInfo) -> some View {
        SidebarRow(info: info,
                   isLive: info.id == model.currentID,
                   isOpen: info.id == model.selection && !model.showingDeleted,
                   isHeld: drag.id == info.id,
                   look: rowLook)
            .onTapGesture {
                model.selection = info.id
                focused = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.selection = info.id }
            .contextMenu { recordingMenu(info) }
            .onDrag {
                drag.began(info.id)
                let provider = NSItemProvider()
                provider.register(RecordingDrag(id: info.id))
                provider.suggestedName = info.title
                return provider
            } preview: {
                LiftedRow(title: info.title, meta: info.id == model.currentID ? "Recording now" : SidebarRow.meta(info))
            }
            .popover(isPresented: Binding(get: { iconFor == info.id }, set: { if !$0 { iconFor = nil } }),
                     arrowEdge: .trailing) {
                IconPicker(icon: info.icon, color: info.iconColor ?? .ink) { icon, color in
                    model.setIcon(info.id, icon, color: color)
                }
            }
    }

    /// The recordings you can see, top to bottom, for the arrow keys.
    private var visibleIDs: [UUID] {
        var ids: [UUID] = []
        for group in store.groups where !group.collapsed {
            ids += model.recordings.filter { $0.groupID == group.id }.map(\.id)
        }
        if !recentsCollapsed {
            ids += model.recordings.filter { store.group($0.groupID) == nil }.map(\.id)
        }
        return ids
    }

    private func step(_ by: Int) -> KeyPress.Result {
        let ids = visibleIDs
        guard !ids.isEmpty else { return .ignored }
        guard let current = model.selection, let i = ids.firstIndex(of: current) else {
            model.selection = by > 0 ? ids.first : ids.last
            return .handled
        }
        let next = i + by
        if ids.indices.contains(next) { model.selection = ids[next] }
        return .handled
    }

    private func newGroup() {
        let group = store.add()
        model.renameGroupRequest = group.id
    }

    @ViewBuilder private func recordingMenu(_ info: RecordingInfo) -> some View {
        Button("Rename…") {
            newTitle = info.title
            renaming = info
        }
        Button("Change Icon…") { iconFor = info.id }
        Menu("Move to Group") {
            ForEach(store.groups) { group in
                Button(group.name) { model.moveRecording(info.id, to: group.id) }
                    .disabled(info.groupID == group.id)
            }
            if !store.groups.isEmpty { Divider() }
            Button("Recents (no group)") { model.moveRecording(info.id, to: nil) }
                .disabled(store.group(info.groupID) == nil)
            Divider()
            Button("New Group…") {
                let group = store.add()
                model.moveRecording(info.id, to: group.id)
                model.renameGroupRequest = group.id
            }
        }
        Button("Show in Finder") { model.showInFinder(info) }
        Divider()
        if info.id != model.currentID {
            Button(info.hasAudio ? "Play Audio" : "Audio Deleted") { model.playAudio(info.id) }
                .disabled(!info.hasAudio)
        }
        Button(SidebarView.deleteAudioTitle(info, blocker: model.audioDeleteBlocker(info.id))) {
            model.deleteAudio(info.id)
        }
        .disabled(model.audioDeleteBlocker(info.id) != nil)
        if info.hasAudio, info.id != model.currentID {
            Toggle("Keep Audio", isOn: Binding(
                get: { info.keepAudio == true },
                set: { model.setKeepAudio(info.id, $0) }))
        }
        Divider()
        Button("Delete") { model.delete(info.id) }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!model.canDelete(info.id))
    }

    /// "Delete Audio Only (115 MB)", so it's clear what you get back,
    /// or why it can't be used right now.
    static func deleteAudioTitle(_ info: RecordingInfo, blocker: String?) -> String {
        if !info.hasAudio { return "Delete Audio Only (already deleted)" }
        if let blocker { return "Delete Audio Only (\(blocker.lowercased()))" }
        guard let bytes = RecordingStore.audioSize(info.id) else { return "Delete Audio Only" }
        return "Delete Audio Only (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
    }
}

/// Where a held recording can land: a group, or Recents (no group).
enum SidebarSpot: Hashable {
    case group(UUID)
    case recents

    var groupID: UUID? {
        if case .group(let id) = self { return id }
        return nil
    }
}

/// The recording being dragged, and the place it's over. One for the app.
@MainActor
@Observable
final class SidebarDrag {
    static let shared = SidebarDrag()

    /// The row being held: it shows as a gap while this is set.
    private(set) var id: UUID?
    /// The group (or Recents) lit up under the pointer.
    var target: SidebarSpot?
    /// Kept after the drag ends, for a drop that arrives late.
    private(set) var lastID: UUID?
    private var watch: Task<Void, Never>?
    private var spring: Task<Void, Never>?

    /// Called when a row starts being dragged. macOS doesn't tell SwiftUI
    /// when a drag is cancelled or dropped outside Verbatim, so this
    /// watches the mouse button and ends the drag when it's let go.
    func began(_ id: UUID) {
        lastID = id
        // Not in the middle of macOS starting the drag.
        Task { @MainActor in
            self.id = id
            self.watch?.cancel()
            self.watch = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    if NSEvent.pressedMouseButtons & 1 == 0 {
                        self?.end()
                        return
                    }
                }
            }
        }
    }

    func end() {
        watch?.cancel()
        spring?.cancel()
        id = nil
        target = nil
    }

    /// Resting on a folded group for a moment opens it, like Finder.
    func springLoad(_ groupID: UUID) {
        spring?.cancel()
        spring = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self, self.target == .group(groupID) else { return }
            withAnimation(.snappy(duration: 0.22)) {
                GroupStore.shared.update(groupID) { $0.collapsed = false }
            }
        }
    }

    func stopSpring() { spring?.cancel() }
}

/// A group (or Recents) as a drop zone. Proposes "move", so macOS shows no
/// green plus inside Verbatim (the plus means "copy"). The methods are
/// nonisolated and step onto the main actor themselves, which works whether
/// or not the SDK marks DropDelegate as main-actor (drops arrive on main).
struct SidebarDropDelegate: DropDelegate {
    let spot: SidebarSpot
    let model: RecorderModel
    let drag: SidebarDrag

    /// The held recording isn't already here.
    @MainActor private func isNewPlace() -> Bool {
        guard let id = drag.id ?? drag.lastID, let info = model.info(id) else { return false }
        return GroupStore.shared.group(info.groupID)?.id != spot.groupID
    }

    nonisolated func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.verbatimRecording])
    }

    nonisolated func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard isNewPlace() else { return }
            drag.target = spot
            if let id = spot.groupID, GroupStore.shared.group(id)?.collapsed == true {
                drag.springLoad(id)
            }
        }
    }

    nonisolated func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated {
            let fresh = isNewPlace()
            if fresh, drag.target != spot { drag.target = spot }
            return DropProposal(operation: fresh ? .move : .forbidden)
        }
    }

    nonisolated func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            if drag.target == spot {
                drag.target = nil
                drag.stopSpring()
            }
        }
    }

    nonisolated func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            defer { drag.end() }
            guard isNewPlace(), let id = drag.id ?? drag.lastID, let rec = model.info(id) else { return false }
            let before = GroupStore.shared.group(rec.groupID)?.id
            let model = model
            withAnimation(.snappy(duration: 0.25)) {
                model.moveRecording(id, to: spot.groupID)
                if let g = spot.groupID { GroupStore.shared.update(g) { $0.collapsed = false } }
            }
            let place = spot.groupID.flatMap { GroupStore.shared.group($0)?.name } ?? "Recents"
            model.offerLineUndo("Moved \(rec.title) to \(place).") {
                withAnimation(.snappy(duration: 0.25)) { model.moveRecording(id, to: before) }
            }
            return true
        }
    }
}

/// The tint and outline on a group while a recording is held over it.
struct DropHighlight: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.accent.opacity(on ? 0.14 : 0))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(on ? 0.55 : 0), lineWidth: 1.5)
            }
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// A group's name in the sidebar: its icon (click to change), the name, and +
/// to start a recording in it. While a recording is held over the group,
/// the + gives way to "Move here".
struct GroupHeader: View {
    @Environment(RecorderModel.self) private var model
    let group: RecordingGroup
    var isTarget = false
    @State private var picking = false

    private var store: GroupStore { .shared }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                picking = true
            } label: {
                ItemIcon(name: group.icon, color: group.color, size: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change the icon")
            .accessibilityLabel("Change icon for \(group.name)")
            .popover(isPresented: $picking, arrowEdge: .trailing) {
                IconPicker(icon: group.icon, color: group.color) { icon, color in
                    store.update(group.id) {
                        $0.icon = icon
                        $0.color = color
                    }
                }
            }

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    store.update(group.id) { $0.collapsed.toggle() }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(group.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(group.collapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(group.collapsed ? "Show recordings" : "Fold up")
            .accessibilityLabel("\(group.name), \(group.collapsed ? "folded" : "open")")

            Spacer(minLength: 4)

            if isTarget {
                MoveHereLabel()
            } else {
                Button {
                    Task { await model.start(in: group.id) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(model.isBusy)
                .help(model.isBusy ? "Stop the recording first" : "New recording in \(group.name)")
                .accessibilityLabel("New recording in \(group.name)")
            }
        }
        .frame(minHeight: 22)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .padding(.top, 5)
        .contextMenu {
            Button("New Recording Here") { Task { await model.start(in: group.id) } }
                .disabled(model.isBusy)
            Divider()
            Button("Rename Group…") { model.renameGroupRequest = group.id }
            Button("Change Icon…") { picking = true }
            Divider()
            Button("Move Up") { store.move(group.id, by: -1) }
                .disabled(store.groups.first?.id == group.id)
            Button("Move Down") { store.move(group.id, by: 1) }
                .disabled(store.groups.last?.id == group.id)
            Divider()
            Button("Delete Group") { model.deleteGroup(group.id) }
        }
    }
}

/// "Recents": recordings not in any group, folds like a group. Dropping a
/// recording here takes it out of its group.
struct RecentsHeader: View {
    @Binding var collapsed: Bool
    var isTarget = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text("Recents")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                Spacer()
                if isTarget { MoveHereLabel() }
            }
            .frame(minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .padding(.top, 5)
        .accessibilityLabel("Recents, \(collapsed ? "folded" : "open")")
    }
}

/// "Recording now, 12 min". Its own view so the ticking clock redraws only
/// this bit of text, not the whole sidebar.
struct LiveRowMeta: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        let len = RecorderModel.minutesText(model.elapsed)
        Text(model.phase == .paused ? "Paused, \(len)" : "Recording now, \(len)")
    }
}

/// Shown in a group's header while a recording is held over it.
struct MoveHereLabel: View {
    var body: some View {
        Text("Move here")
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.trailing, 4)
    }
}

/// One recording in the sidebar, on its own box (design pass). The box gets
/// darker under the pointer and is clearly marked when the recording is open.
/// While it's being dragged it shows as an empty outline: the gap it left.
struct SidebarRow: View {
    let info: RecordingInfo
    let isLive: Bool
    let isOpen: Bool
    var isHeld = false
    let look: RowLook
    @State private var hovering = false

    /// Paper cards: the open card is filled with ink, so its text is paper.
    private var inverted: Bool { look == .cards && isOpen && !isHeld }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isLive {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
            } else if let icon = info.icon {
                Group {
                    if inverted {
                        // On the ink card the icon's own color would vanish.
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.paper)
                            .frame(width: 17, height: 17)
                    } else {
                        ItemIcon(name: icon, color: info.iconColor ?? .ink, size: 11)
                    }
                }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.body.weight(isOpen && look == .soft ? .semibold : .medium))
                    .lineLimit(1)
                Group {
                    if isLive { LiveRowMeta() } else { Text(Self.meta(info)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(inverted ? Theme.paper : Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .opacity(isHeld ? 0 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { box }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    @ViewBuilder private var box: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if isHeld {
            shape.strokeBorder(Theme.ink.opacity(0.13), lineWidth: 1.5)
        } else {
            switch look {
            case .soft:
                shape.fill(Theme.ink.opacity(isOpen ? 0.15 : hovering ? 0.085 : 0.045))
            case .cards:
                shape.fill(isOpen ? Theme.ink : Theme.card)
                    .shadow(color: .black.opacity(hovering ? 0.14 : 0.09),
                            radius: hovering ? 3 : 1, y: hovering ? 1.5 : 0.5)
            }
        }
    }

    static func meta(_ info: RecordingInfo) -> String {
        let day = RecorderModel.dayTitle(info.createdAt)
        // Named after the day already: say the time instead of the day twice.
        let when = info.title.contains(day) ? info.createdAt.formatted(date: .omitted, time: .shortened) : day
        let base = "\(when), \(RecorderModel.minutesText(info.duration))"
        if !info.hasAudio { return base + ", no audio" }
        // Step 9: a warning a few days before old audio goes.
        if let left = AudioCleanup.daysLeft(info), left <= 3 {
            return when + (left <= 1 ? ", audio deletes tomorrow" : ", audio deletes in \(left) days")
        }
        return base
    }
}

/// The picture that follows the pointer while a recording is dragged: the
/// row as a card, lifted (a bit bigger, tilted, with a shadow). Padding
/// leaves room for the shadow. No environment: macOS draws it on its own.
struct LiftedRow: View {
    let title: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text(meta)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 220, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
        .scaleEffect(1.04)
        .rotationEffect(.degrees(-1.6))
        .padding(18)
    }
}

/// Always at the top of the sidebar, like "New chat" in Claude.
/// Opens the start screen (recording begins from its Start button, Ryan's
/// ask); while recording it jumps back to it.
struct NewRecordingButton: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        SidebarAction(
            title: model.isBusy ? (model.phase == .paused ? "Paused, go to it" : "Recording now") : "New recording",
            icon: model.isBusy ? "waveform" : "plus",
            shortcut: model.isBusy ? nil : "⌘N",
            help: model.isBusy ? "Go to the recording in progress" : "Open a new recording (⌘N)",
            bold: true
        ) {
            model.showNewRecording()
        }
    }
}

/// One line at the top of the sidebar: icon, words, shortcut. Shaded on hover.
struct SidebarAction: View {
    let title: String
    let icon: String
    var shortcut: String?
    var help: String
    var bold = false
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .fontWeight(bold ? .semibold : .regular)
                    .frame(width: 16)
                Text(title)
                    .fontWeight(bold || selected ? .medium : .regular)
                    .lineLimit(1)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.1) : hovering ? Color.primary.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// "Recently deleted 3" at the top of the sidebar (step 9). Hidden when empty.
struct RecentlyDeletedButton: View {
    @Environment(RecorderModel.self) private var model
    private var deleted: RecentlyDeleted { .shared }

    var body: some View {
        if !deleted.items.isEmpty {
            SidebarAction(
                title: "Recently deleted",
                icon: "trash",
                shortcut: "\(deleted.items.count)",
                help: "Deleted recordings stay here for \(RecentlyDeleted.keepDays) days",
                selected: model.showingDeleted
            ) {
                model.selection = nil
                model.showingDeleted = true
            }
        }
    }
}

/// What a dragged recording carries. Inside Verbatim: which recording, so it
/// can move between groups. Dropped in another app (Claude, Finder, Notes):
/// its transcript as a Markdown file, named like an export.
struct RecordingDrag: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .verbatimRecording)
        FileRepresentation(exportedContentType: .markdownText) { item in
            let url = try await MainActor.run { try item.writeTranscript() }
            return SentTransferredFile(url)
        }
    }

    /// Writes the transcript to a fresh temporary folder and returns the file.
    @MainActor
    private func writeTranscript() throws -> URL {
        let model = RecorderModel.shared
        guard let info = model.info(id) else { throw CocoaError(.fileNoSuchFile) }
        let lines = model.shownLines(id).map(\.line)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Verbatim drag \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = RecorderModel.freeName(for: info, format: .markdown, in: folder)
        let url = folder.appending(path: name)
        try RecorderModel.text(lines, info: info, markdown: true).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

extension UTType {
    /// Declared in Support/Info.plist (UTExportedTypeDeclarations).
    static let verbatimRecording = UTType(exportedAs: "com.rywnswn.verbatim.recording")
    static let markdownText = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}
