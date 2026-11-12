import Foundation

/// Verbatim as a tool for the Claude desktop app (Ryan's ask, 2026-11-12).
/// Claude starts a second copy of Verbatim with `--mcp` and talks to it over
/// stdin and stdout using the Model Context Protocol (JSON-RPC, one message
/// per line). This copy has no window and only READS the files on disk, so it
/// is safe next to the real app, even while recording. Everything stays on
/// the Mac until Claude asks for a transcript in a chat.
/// Spec: modelcontextprotocol.io/specification/2025-06-18
enum MCPServer {
    private static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let message = json as? [String: Any] {
                handle(message)
            } else if let batch = json as? [[String: Any]] {
                batch.forEach(handle)
            }
        }
    }

    private static func handle(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return } // an answer, not a question
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        // No id = a notification: never answered.
        guard let id, !(id is NSNull) else { return }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let capabilities: [String: Any] = ["tools": [String: Any]()]
            let server: [String: Any] = ["name": "verbatim", "title": "Verbatim", "version": AppInfo.version]
            reply(id, [
                "protocolVersion": versions.contains(asked) ? asked : versions[0],
                "capabilities": capabilities,
                "serverInfo": server,
                "instructions": "Verbatim records the user's classes on this Mac and writes a transcript. Use these tools to list recordings, read a transcript and search all transcripts. \"latest\" means the class being recorded right now, or else the newest one. Transcripts are speech-to-text, so names and unusual words can be misheard. Read only: nothing here changes or deletes anything.",
            ])
        case "ping":
            reply(id, [String: Any]())
        case "tools/list":
            reply(id, ["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let result = call(name, args) else {
                fail(id, -32602, "Unknown tool: \(name)")
                return
            }
            let content: [[String: Any]] = [["type": "text", "text": result.text]]
            reply(id, ["content": content, "isError": result.isError])
        case "resources/list":
            reply(id, ["resources": [Any]()])
        case "prompts/list":
            reply(id, ["prompts": [Any]()])
        default:
            fail(id, -32601, "Method not found: \(method)")
        }
    }

    private static func reply(_ id: Any, _ result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func fail(_ id: Any, _ code: Int, _ text: String) {
        let error: [String: Any] = ["code": code, "message": text]
        send(["jsonrpc": "2.0", "id": id, "error": error])
    }

    /// One line per message. JSONSerialization never puts a raw newline inside.
    private static func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    // MARK: - Tools

    private static func property(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static func tool(_ name: String, _ title: String, _ description: String,
                             properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        let hints: [String: Any] = ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]
        return ["name": name, "title": title, "description": description, "inputSchema": schema, "annotations": hints]
    }

    private static var tools: [[String: Any]] {
        let list = tool(
            "list_recordings", "List recordings",
            "Lists the classes and files recorded in Verbatim, newest first: name, group (the class, like \"English 2026\"), date, length, number of lines and id. A recording marked BEING RECORDED NOW is still going.",
            properties: [
                "group": property("string", "Only recordings in a group whose name contains this, like \"English\"."),
                "limit": property("integer", "How many to list. Default 30."),
            ]
        )
        let read = tool(
            "read_transcript", "Read a transcript",
            "Reads one recording's transcript: one line per sentence or two, with the time, the speaker if known, and [MARKED] on lines the user marked as important. Works on the class being recorded right now too (about 10 seconds behind).",
            properties: [
                "recording": property("string", "The recording's id, words from its name, or \"latest\" (the one being recorded now, or else the newest)."),
                "last_minutes": property("number", "Only the last N minutes, for \"what did he just say\"."),
                "from_minute": property("number", "Start this many minutes into the recording."),
                "to_minute": property("number", "Stop this many minutes into the recording."),
                "marked_only": property("boolean", "Only the lines the user marked."),
            ],
            required: ["recording"]
        )
        let search = tool(
            "search_transcripts", "Search transcripts",
            "Finds lines that contain all the given words (any letter case) in every recording, or in one. Returns each hit with its recording, time and speaker.",
            properties: [
                "query": property("string", "Words to look for, like \"quiz\" or \"sky god\"."),
                "recording": property("string", "Search only this recording: its id, words from its name, or \"latest\"."),
                "limit": property("integer", "The most hits to return. Default 40."),
            ],
            required: ["query"]
        )
        return [list, read, search]
    }

    private static func call(_ name: String, _ args: [String: Any]) -> (text: String, isError: Bool)? {
        switch name {
        case "list_recordings": return list(args)
        case "read_transcript": return read(args)
        case "search_transcripts": return search(args)
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func list(_ args: [String: Any]) -> (text: String, isError: Bool) {
        let groups = Library.groupNames()
        var all = Library.recordings()
        let total = all.count
        if let g = (args["group"] as? String)?.lowercased(), !g.isEmpty {
            all = all.filter { r in r.groupID.flatMap { groups[$0] }?.lowercased().contains(g) ?? false }
        }
        guard !all.isEmpty else {
            return (total == 0 ? "There are no recordings in Verbatim yet." : "No recordings in a group like that. Groups: \(groups.values.sorted().joined(separator: ", ")).", false)
        }
        let limit = max(1, min(200, Int(number(args["limit"]) ?? 30)))
        var out = all.prefix(limit).enumerated().map { i, r in
            "\(i + 1). " + Library.summary(r, groups: groups, lineCount: Library.lines(r).lines.count)
        }
        if all.count > limit { out.append("(\(all.count - limit) older ones not shown. Ask with a bigger limit to see them.)") }
        return (out.joined(separator: "\n"), false)
    }

    private static func read(_ args: [String: Any]) -> (text: String, isError: Bool) {
        let all = Library.recordings()
        let info: RecordingInfo
        switch Library.find(args["recording"] as? String ?? "latest", in: all) {
        case .one(let r): info = r
        case .problem(let p): return (p, true)
        }
        let (everyLine, labels) = Library.lines(info)
        let marked = Markers.markedStarts(everyLine, info.markers)
        var lines = everyLine
        if let last = number(args["last_minutes"]), last > 0 {
            let end = everyLine.map(\.end).max() ?? 0
            lines = lines.filter { $0.end >= end - last * 60 }
        }
        if let from = number(args["from_minute"]) { lines = lines.filter { $0.end >= from * 60 } }
        if let to = number(args["to_minute"]) { lines = lines.filter { $0.start <= to * 60 } }
        if args["marked_only"] as? Bool == true { lines = lines.filter { marked.contains($0.start) } }

        var head = ["# \(info.title)"]
        if let g = info.groupID.flatMap({ Library.groupNames()[$0] }) { head.append("Group: \(g)") }
        head.append("Started: \(Library.day(info.createdAt)), \(max(1, Int((info.duration / 60).rounded()))) min long")
        if Library.isLive(info) { head.append("Still being recorded. The newest words can be about 10 seconds behind.") }
        if let file = info.importedFrom { head.append("Imported from the file \(file). Times count from the start of the file.") }
        head.append("id: \(info.id.uuidString)")

        if everyLine.isEmpty {
            head.append("")
            head.append(Library.isLive(info) ? "No words yet." : "This recording has no transcript (yet).")
            return (head.joined(separator: "\n"), false)
        }
        head.append(lines.count == everyLine.count ? "\(lines.count) lines." : "\(lines.count) of \(everyLine.count) lines (the part asked for).")
        head.append("")
        var body: [String] = []
        var size = 0
        for line in lines {
            let text = Library.text(line, in: info, labels: labels, marked: marked.contains(line.start))
            size += text.utf8.count + 1
            if size > 220_000 {
                body.append("(Stopped here: the rest is too long for one go. Call again with from_minute \(Int(line.start / 60)).)")
                break
            }
            body.append(text)
        }
        if lines.isEmpty { body.append("No lines in that part.") }
        return ((head + body).joined(separator: "\n"), false)
    }

    private static func search(_ args: [String: Any]) -> (text: String, isError: Bool) {
        let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return ("Give some words to look for in \"query\".", true) }
        var all = Library.recordings()
        if let one = args["recording"] as? String, !one.trimmingCharacters(in: .whitespaces).isEmpty {
            switch Library.find(one, in: all) {
            case .one(let r): all = [r]
            case .problem(let p): return (p, true)
            }
        }
        let limit = max(1, min(200, Int(number(args["limit"]) ?? 40)))
        let groups = Library.groupNames()
        var out: [String] = []
        var hits = 0
        var more = 0
        for info in all {
            let (lines, labels) = Library.lines(info)
            let found = lines.filter { line in
                let text = line.text.lowercased()
                return words.allSatisfy { text.contains($0) }
            }
            guard !found.isEmpty else { continue }
            if hits >= limit {
                more += found.count
                continue
            }
            let marked = Markers.markedStarts(lines, info.markers)
            out.append("## " + Library.summary(info, groups: groups, lineCount: nil))
            for line in found {
                if hits >= limit {
                    more += 1
                    continue
                }
                out.append(Library.text(line, in: info, labels: labels, marked: marked.contains(line.start)))
                hits += 1
            }
            out.append("")
        }
        if hits == 0 {
            return ("No line contains \"\(query)\" in \(all.count == 1 ? "that recording" : "\(all.count) recordings"). Transcripts are speech-to-text, so try another spelling or a nearby word.", false)
        }
        if more > 0 { out.append("(\(more) more hits not shown. Ask with a bigger limit, or search one recording.)") }
        return (out.joined(separator: "\n"), false)
    }
}
