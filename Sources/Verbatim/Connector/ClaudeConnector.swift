import AppKit
import Foundation

/// Hooks Verbatim into the Claude desktop app (Settings > Claude). Claude
/// keeps its list of local tools in one file,
/// ~/Library/Application Support/Claude/claude_desktop_config.json, under
/// "mcpServers". Connect adds a "verbatim" entry there that starts this app
/// with `--mcp` (see `MCPServer`); nothing else in the file is touched, and
/// a copy of the file as it was is kept next to it the first time.
enum ClaudeConnector {
    enum State: Equatable {
        /// The Claude desktop app isn't on this Mac.
        case noClaude
        case notConnected
        case connected
        /// Connected, but to a copy of Verbatim that is somewhere else now.
        case moved
    }

    struct Problem: LocalizedError {
        var text: String
        var errorDescription: String? { text }
    }

    static let name = "verbatim"
    static let downloadURL = URL(string: "https://claude.ai/download")!

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Claude", directoryHint: .isDirectory)
    }

    private static var configURL: URL { folder.appending(path: "claude_desktop_config.json") }

    private static var command: String { Bundle.main.executablePath ?? "" }

    private static var claudeInstalled: Bool {
        FileManager.default.fileExists(atPath: folder.path)
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app")
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
    }

    static func state() -> State {
        guard claudeInstalled else { return .noClaude }
        guard let config = try? readConfig(),
              let servers = config["mcpServers"] as? [String: Any],
              let entry = servers[name] as? [String: Any] else { return .notConnected }
        return entry["command"] as? String == command ? .connected : .moved
    }

    static func connect() throws {
        guard !command.isEmpty else { throw Problem(text: "Verbatim couldn't find itself on disk.") }
        // Opened straight from Downloads, macOS runs a hidden temporary copy.
        guard !command.contains("/AppTranslocation/") else {
            throw Problem(text: "Move Verbatim into your Applications folder first, open it from there, then connect.")
        }
        var config = try readConfig()
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers[name] = ["command": command, "args": ["--mcp"]]
        config["mcpServers"] = servers
        try write(config)
    }

    static func disconnect() throws {
        var config = try readConfig()
        guard var servers = config["mcpServers"] as? [String: Any] else { return }
        servers[name] = nil
        config["mcpServers"] = servers
        try write(config)
    }

    /// An empty or missing file is fine. A file that isn't readable JSON is
    /// left alone: better no connection than breaking Claude's settings.
    private static func readConfig() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Problem(text: "Claude's settings file couldn't be read, so nothing was changed. In Claude: Settings > Developer > Edit Config, and check the file.")
        }
        return config
    }

    private static func write(_ config: [String: Any]) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let backup = folder.appending(path: "claude_desktop_config.before-verbatim.json")
            if fm.fileExists(atPath: configURL.path), !fm.fileExists(atPath: backup.path) {
                try? fm.copyItem(at: configURL, to: backup)
            }
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw Problem(text: "Couldn't save Claude's settings file: \(error.localizedDescription)")
        }
    }
}
