import Foundation
import Observation
import SwiftUI

/// A sidebar group, one per class ("English 2026", "World Studies 2026"),
/// with an icon Ryan picks (step 10). Recordings point at it with
/// `RecordingInfo.groupID`; recordings without one show under Recents.
struct RecordingGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// An SF Symbol name from `IconCatalog`, nil for no icon.
    var icon: String?
    var color: IconColor = .ink
    var collapsed = false
}

/// The soft colors an icon can have. Ink is the default (matches the app).
enum IconColor: String, Codable, CaseIterable, Identifiable {
    case ink, blue, green, red, amber, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .ink: Theme.ink
        case .blue: Theme.iconBlue
        case .green: Theme.iconGreen
        case .red: Theme.iconRed
        case .amber: Theme.iconAmber
        case .purple: Theme.iconPurple
        }
    }

    var label: String { rawValue.capitalized }
}

/// Saved in App Support/Verbatim/groups.json, in sidebar order.
@MainActor
@Observable
final class GroupStore {
    static let shared = GroupStore()

    private struct File: Codable {
        var formatVersion = 1
        var groups: [RecordingGroup]
    }

    private(set) var groups: [RecordingGroup] = []
    /// The group a new recording goes into from the start screen and menu bar.
    /// Remembered, so the next class lands in the same place.
    var lastUsedID: UUID? {
        didSet { UserDefaults.standard.set(lastUsedID?.uuidString, forKey: "lastUsedGroup") }
    }

    private static var url: URL {
        RecordingStore.root.deletingLastPathComponent().appending(path: "groups.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            groups = file.groups
        }
        let last = UserDefaults.standard.string(forKey: "lastUsedGroup").flatMap(UUID.init)
        lastUsedID = groups.contains { $0.id == last } ? last : nil
    }

    func group(_ id: UUID?) -> RecordingGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    /// "New group", "New group 2", ... so two new ones are never mixed up.
    @discardableResult
    func add() -> RecordingGroup {
        var name = "New group"
        var n = 2
        while groups.contains(where: { $0.name == name }) {
            name = "New group \(n)"
            n += 1
        }
        let group = RecordingGroup(name: name, icon: "folder")
        groups.append(group)
        save()
        return group
    }

    func update(_ id: UUID, _ change: (inout RecordingGroup) -> Void) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[i])
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.name = trimmed }
    }

    /// Up or down one place in the sidebar.
    func move(_ id: UUID, by step: Int) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let j = i + step
        guard groups.indices.contains(j) else { return }
        groups.swapAt(i, j)
        save()
    }

    /// Removes the group. Returns where it was, for Undo.
    func remove(_ id: UUID) -> (group: RecordingGroup, index: Int)? {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return nil }
        let group = groups.remove(at: i)
        if lastUsedID == id { lastUsedID = nil }
        save()
        return (group, i)
    }

    func restore(_ group: RecordingGroup, at index: Int) {
        guard !groups.contains(where: { $0.id == group.id }) else { return }
        groups.insert(group, at: min(index, groups.count))
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(File(groups: groups)).write(to: Self.url, options: .atomic)
    }
}

/// Group actions that also touch recordings.
extension RecorderModel {
    func moveRecording(_ id: UUID, to groupID: UUID?) {
        guard let i = recordingIndex(id), recordings[i].groupID != groupID else { return }
        changeRecording(i) { $0.groupID = groupID }
    }

    func setIcon(_ id: UUID, _ icon: String?, color: IconColor) {
        guard let i = recordingIndex(id) else { return }
        changeRecording(i) {
            $0.icon = icon
            $0.iconColor = icon == nil ? nil : color
        }
    }

    /// Deletes a group. Its recordings move to Recents (nothing is lost),
    /// with Undo in the bottom bar.
    func deleteGroup(_ groupID: UUID) {
        let store = GroupStore.shared
        let members = recordings.filter { $0.groupID == groupID }.map(\.id)
        guard let removed = store.remove(groupID) else { return }
        for id in members { moveRecording(id, to: nil) }
        let what = members.isEmpty ? "" : members.count == 1 ? " Its recording is in Recents." : " Its \(members.count) recordings are in Recents."
        offerLineUndo("Deleted \(removed.group.name).\(what)") { [weak self] in
            store.restore(removed.group, at: removed.index)
            for id in members { self?.moveRecording(id, to: groupID) }
        }
    }
}
