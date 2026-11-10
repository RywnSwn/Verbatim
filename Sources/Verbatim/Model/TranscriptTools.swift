import AppKit
import Foundation
import UniformTypeIdentifiers

/// How times show in the gutter (Settings > General).
enum TimeStyle: String, CaseIterable {
    /// 10:42
    case clock
    /// 37:12, counted in recorded audio (pauses skipped).
    case sinceStart

    static let key = "timeStyle"
    static let copyKey = "includeTimesWhenCopying"

    static var current: TimeStyle {
        TimeStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .clock
    }

    static var includeInCopies: Bool { UserDefaults.standard.bool(forKey: copyKey) }
}

/// One search hit: which line, and which hit inside that line.
struct SearchMatch: Hashable {
    var source: LineSource
    var start: Double
    var occurrence: Int

    /// Same id the transcript list uses for the row, so it can scroll there.
    var rowID: String { TranscriptRow.id(source, start) }
}

enum TranscriptRow {
    static func id(_ source: LineSource, _ start: Double) -> String {
        "\(source == .live ? "l" : "c")\(start)"
    }
}

/// Copy, export and search for the transcript on screen (step 6).
extension RecorderModel {
    // MARK: - Lines on screen

    /// An old Whisper transcript (if any), then the live text after it.
    /// Same as what the transcript view shows (without half-said words).
    func shownLines(_ id: UUID) -> [(line: Transcript.Line, source: LineSource)] {
        let transcript = Transcriber.shared.transcripts[id]
        var rows = (transcript?.lines ?? []).map { ($0, LineSource.checked) }
        if transcript?.finished != true {
            let live = LiveTranscriber.shared.texts[id]?.unchecked(after: transcript?.doneUpTo ?? 0) ?? []
            rows += live.map { ($0, LineSource.live) }
        }
        return rows.map { (line: $0.0, source: $0.1) }
    }

    var shownID: UUID? {
        guard let id = selection, recordings.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    var hasShownLines: Bool { shownID.map { !shownLines($0).isEmpty } ?? false }

    // MARK: - Copy

    enum CopyKind { case all, new, lastTenMinutes }

    /// Lines that "Copy new since last copy" would copy.
    func newLines(_ id: UUID) -> [Transcript.Line] {
        let lines = shownLines(id).map(\.line)
        guard let from = info(id)?.copiedUpTo else { return lines }
        return lines.filter { $0.middle > from }
    }

    func copy(_ kind: CopyKind) {
        guard let id = shownID, let info = info(id) else { return }
        let all = shownLines(id).map(\.line)
        guard !all.isEmpty else {
            copyFeedback = CopyFeedback(text: "Nothing to copy yet")
            return
        }
        let lines: [Transcript.Line]
        switch kind {
        case .all:
            lines = all
        case .new:
            lines = newLines(id)
            if lines.isEmpty {
                copyFeedback = CopyFeedback(text: "Nothing new since last copy")
                return
            }
        case .lastTenMinutes:
            let end = all.map(\.end).max() ?? 0
            lines = all.filter { $0.end > end - 600 }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.text(lines, info: info, markdown: false), forType: .string)
        copyFeedback = CopyFeedback(text: lines.count == 1 ? "Copied 1 line" : "Copied \(lines.count) lines")

        // Remember where this copy ended, for "Copy new since last copy".
        if let end = lines.map(\.end).max() {
            setCopiedUpTo(id, max(end, info.copiedUpTo ?? 0))
        }
    }

    /// Lines as text for Claude or a file. One line each; times in front only
    /// if Settings says so. Lines with a speaker are in script format,
    /// `[Mr. Yurt]: "text"` (Markdown: `**Mr. Yurt:** text`). Markdown puts a
    /// blank line between lines so each one stays its own paragraph.
    static func text(_ lines: [Transcript.Line], info: RecordingInfo, markdown: Bool) -> String {
        let withTimes = TimeStyle.includeInCopies
        let labels = Speakers.labeler(info.id)
        let rows = lines.map { line in
            var row = line.text
            if let name = labels.name(line) {
                row = markdown ? "**\(name):** \(line.text)" : "[\(name)]: \"\(line.text)\""
            }
            return withTimes ? "[\(info.timeLabel(line.start))] \(row)" : row
        }
        return rows.joined(separator: markdown ? "\n\n" : "\n")
    }

    // MARK: - Export

    enum ExportFormat {
        case text, markdown

        var fileExtension: String { self == .text ? "txt" : "md" }
        var type: UTType { self == .text ? .plainText : (UTType(filenameExtension: "md") ?? .plainText) }
    }

    func export(_ format: ExportFormat) {
        guard let id = shownID, let info = info(id) else { return }
        let lines = shownLines(id).map(\.line)
        guard !lines.isEmpty else { return }

        let panel = NSSavePanel()
        let folder = Self.lastExportFolder
        panel.directoryURL = folder
        panel.nameFieldStringValue = Self.freeName(for: info, format: format, in: folder)
        panel.allowedContentTypes = [format.type]
        panel.canCreateDirectories = true
        panel.title = "Export Transcript"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try (Self.text(lines, info: info, markdown: format == .markdown) + "\n")
                .write(to: url, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: Self.exportFolderKey)
            showFile(url, text: "Saved \(url.lastPathComponent).")
        } catch {
            show("Couldn't save \(url.lastPathComponent): \(error.localizedDescription) Try another folder.")
        }
    }

    private static let exportFolderKey = "lastExportFolder"

    private static var lastExportFolder: URL {
        if let path = UserDefaults.standard.string(forKey: exportFolderKey),
           FileManager.default.fileExists(atPath: path) {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// "2026-11-10 English.md", or "2026-11-10 English (2).md" if that's taken.
    static func freeName(for info: RecordingInfo, format: ExportFormat, in folder: URL) -> String {
        let date = info.createdAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let title = info.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = "\(date) \(title)"
        var name = "\(base).\(format.fileExtension)"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
            name = "\(base) (\(n)).\(format.fileExtension)"
            n += 1
        }
        return name
    }

    // MARK: - Search

    /// Every hit of the search text, in reading order. Ignores case and accents.
    func searchMatches(_ id: UUID) -> [SearchMatch] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var matches: [SearchMatch] = []
        for row in shownLines(id) {
            let count = Self.ranges(of: query, in: row.line.text).count
            for k in 0..<count {
                matches.append(SearchMatch(source: row.source, start: row.line.start, occurrence: k))
            }
        }
        return matches
    }

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex,
              let r = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            result.append(r)
            from = r.isEmpty ? text.index(after: r.lowerBound) : r.upperBound
        }
        return result
    }

    /// Cmd+G / Shift+Cmd+G / Enter in the search field.
    func nextMatch(_ step: Int) {
        guard let id = shownID else { return }
        let count = searchMatches(id).count
        guard count > 0 else { return }
        matchIndex = ((matchIndex + step) % count + count) % count
        matchJump += 1
    }

    // MARK: - Helpers

    private func info(_ id: UUID) -> RecordingInfo? { recordings.first { $0.id == id } }
}
