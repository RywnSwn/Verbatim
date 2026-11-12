import Foundation

/// The recordings on disk, read for Claude (see `MCPServer`). Plain file
/// reading only: it must never touch RecorderModel, LiveTranscriber or the
/// other live objects, because this runs in a second copy of Verbatim that
/// Claude starts, while the real app may be recording.
enum Library {
    /// Group names by id, from groups.json.
    static func groupNames() -> [UUID: String] {
        struct File: Decodable {
            struct Group: Decodable {
                var id: UUID
                var name: String
            }
            var groups: [Group]
        }
        let url = RecordingStore.root.deletingLastPathComponent().appending(path: "groups.json")
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return Dictionary(file.groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    /// Newest first.
    static func recordings() -> [RecordingInfo] { RecordingStore.loadAll() }

    /// The lines the app shows for a recording (an old Whisper transcript, if
    /// any, then the live text after it), and who said each one.
    static func lines(_ info: RecordingInfo) -> (lines: [Transcript.Line], labels: Speakers.Labeler) {
        let transcript = TranscriptStore.load(info.id)
        let live = LiveStore.load(info.id)
        var lines = transcript?.lines ?? []
        if transcript?.finished != true {
            lines += live?.unchecked(after: transcript?.doneUpTo ?? 0) ?? []
        }
        return (lines, Speakers.Labeler(lines: live?.lines ?? [], names: live?.voiceNames))
    }

    static func isLive(_ info: RecordingInfo) -> Bool { info.state != .stopped }

    enum Found {
        case one(RecordingInfo)
        case problem(String)
    }

    /// Finds a recording by id, by "latest", or by words from its name.
    static func find(_ raw: String, in all: [RecordingInfo]) -> Found {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !all.isEmpty else { return .problem("There are no recordings in Verbatim yet.") }
        if let id = UUID(uuidString: q) {
            if let r = all.first(where: { $0.id == id }) { return .one(r) }
            return .problem("No recording has the id \(q). Call list_recordings to see the ids.")
        }
        let lower = q.lowercased()
        if lower.isEmpty || ["latest", "last", "newest", "current", "now", "today"].contains(lower) {
            return .one(all.first(where: isLive) ?? all[0])
        }
        let words = lower.split(whereSeparator: \.isWhitespace)
        let matches = all.filter { r in
            let title = r.title.lowercased()
            return words.allSatisfy { title.contains($0) }
        }
        if matches.count == 1 { return .one(matches[0]) }
        if let exact = matches.first(where: { $0.title.lowercased() == lower }),
           matches.filter({ $0.title.lowercased() == lower }).count == 1 {
            return .one(exact)
        }
        if matches.isEmpty {
            return .problem("No recording's name contains \"\(q)\". Call list_recordings to see what there is.")
        }
        let groups = groupNames()
        let list = matches.prefix(8).map { "- " + summary($0, groups: groups, lineCount: nil) }.joined(separator: "\n")
        return .problem("\(matches.count) recordings match \"\(q)\". Call again with the id of the one you want:\n\(list)")
    }

    // MARK: - Text for Claude

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute())
    }

    /// "Anansi and the sky god | English 2026 | Wed 11 Nov 2026, 10:05 | 47 min | id: ..."
    static func summary(_ info: RecordingInfo, groups: [UUID: String], lineCount: Int?) -> String {
        var parts = [info.title]
        if let g = info.groupID.flatMap({ groups[$0] }) { parts.append(g) }
        parts.append(day(info.createdAt))
        parts.append("\(max(1, Int((info.duration / 60).rounded()))) min")
        if let lineCount { parts.append(lineCount == 1 ? "1 line" : "\(lineCount) lines") }
        if isLive(info) { parts.append("BEING RECORDED NOW") }
        if info.importedFrom != nil { parts.append("imported file") }
        parts.append("id: \(info.id.uuidString)")
        return parts.joined(separator: " | ")
    }

    /// Clock time for a class ("10:42"), time since the start for imported files ("37:12").
    static func time(_ seconds: Double, in info: RecordingInfo) -> String {
        if info.importedFrom != nil {
            let s = Int(seconds)
            return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
        return info.wallTime(atSecond: seconds).formatted(date: .omitted, time: .shortened)
    }

    /// "[10:42] Mr. Yurt: So Anansi goes to the sky god.", then the note under it, if any.
    static func text(_ line: Transcript.Line, in info: RecordingInfo, labels: Speakers.Labeler, marked: Bool, note: String?) -> String {
        var out = marked ? "[MARKED] " : ""
        out += "[\(time(line.start, in: info))] "
        if let name = labels.name(line) { out += name + ": " }
        out += line.text
        // What the user typed under the line (things the mic can't hear).
        if let note { out += "\n    (Note: \(note))" }
        return out
    }
}
