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

    enum CopyKind { case all, new, lastTenMinutes, marked }

    /// Lines that "Copy new since last copy" would copy.
    func newLines(_ id: UUID) -> [Transcript.Line] {
        let lines = shownLines(id).map(\.line)
        guard let from = info(id)?.copiedUpTo else { return lines }
        return lines.filter { $0.middle > from }
    }

    /// Copies from the transcript on screen, or from `recording` (the mini
    /// window and menu bar copy from the class being recorded).
    func copy(_ kind: CopyKind, from recording: UUID? = nil) {
        guard let id = recording ?? shownID, let info = info(id) else { return }
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
        case .marked:
            let marked = Markers.markedStarts(all, info.markers)
            lines = all.filter { marked.contains($0.start) }
            if lines.isEmpty {
                copyFeedback = CopyFeedback(text: "Nothing marked yet")
                return
            }
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
        let marked = Markers.markedStarts(RecorderModel.shared.shownLines(info.id).map(\.line), info.markers)
        let rows = lines.map { line in
            var row = line.text
            if let name = labels.name(line) {
                row = markdown ? "**\(name):** \(line.text)" : "[\(name)]: \"\(line.text)\""
            }
            if withTimes { row = "[\(info.timeLabel(line.start))] \(row)" }
            return marked.contains(line.start) ? "⚑ \(row)" : row
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

    /// Settings > Storage > Export Everything (step 9): a zip with every
    /// transcript as .md, the raw data files and settings. No audio.
    func exportEverything() {
        let panel = NSSavePanel()
        panel.directoryURL = Self.lastExportFolder
        let day = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        panel.nameFieldStringValue = "Verbatim Export \(day).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.title = "Export Everything"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Text is made here (it needs the app's state); files and zip in the background.
        let readable = recordings.map { info -> (name: String, text: String) in
            let lines = shownLines(info.id).map(\.line)
            let body = lines.isEmpty ? "(No text.)" : Self.text(lines, info: info, markdown: true)
            return (Self.freeName(for: info, format: .markdown, in: URL(filePath: "/nonexistent")), body + "\n")
        }
        let ids = recordings.map(\.id)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Verbatim", directoryHint: .isDirectory)
        show("Exporting \(recordings.count) transcripts…")
        Task {
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                let fm = FileManager.default
                let temp = fm.temporaryDirectory.appending(path: "Verbatim-export-\(UUID().uuidString)", directoryHint: .isDirectory)
                let top = temp.appending(path: url.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
                defer { try? fm.removeItem(at: temp) }
                do {
                    let texts = top.appending(path: "Transcripts", directoryHint: .isDirectory)
                    try fm.createDirectory(at: texts, withIntermediateDirectories: true)
                    var used: Set<String> = []
                    for item in readable {
                        var name = item.name
                        var n = 2
                        while used.contains(name.lowercased()) {
                            name = item.name.replacingOccurrences(of: ".md", with: " (\(n)).md")
                            n += 1
                        }
                        used.insert(name.lowercased())
                        try item.text.write(to: texts.appending(path: name), atomically: true, encoding: .utf8)
                    }
                    // Raw data, so a future Verbatim could read it back.
                    let data = top.appending(path: "Data/Recordings", directoryHint: .isDirectory)
                    for id in ids {
                        let to = data.appending(path: id.uuidString, directoryHint: .isDirectory)
                        try fm.createDirectory(at: to, withIntermediateDirectories: true)
                        for file in ["recording.json", "live.json", "transcript.json"] {
                            let from = RecordingStore.folder(id).appending(path: file)
                            if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: to.appending(path: file)) }
                        }
                    }
                    for file in ["words.json", "Voices/voices.json"] {
                        let from = support.appending(path: file)
                        if fm.fileExists(atPath: from.path) {
                            try fm.copyItem(at: from, to: top.appending(path: "Data").appending(path: (file as NSString).lastPathComponent))
                        }
                    }
                    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                    let zip = Process()
                    zip.executableURL = URL(filePath: "/usr/bin/ditto")
                    zip.arguments = ["-c", "-k", "--keepParent", top.path, url.path]
                    try zip.run()
                    zip.waitUntilExit()
                    return zip.terminationStatus == 0 ? nil : "the zip couldn't be made"
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let error {
                show("Couldn't export: \(error). Try another folder.")
            } else {
                UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: Self.exportFolderKey)
                showFile(url, text: "Saved \(url.lastPathComponent).")
            }
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

    func info(_ id: UUID) -> RecordingInfo? { recordings.first { $0.id == id } }
}
