import AppKit
import Foundation
import PlumeKit

/// What connects Plume to the terminal and to assistants: the `plume` command, and registering
/// the MCP server with Claude Code and Claude Desktop.
enum Integrations {
    /// The app's binary: it is what the command and the MCP server launch.
    static var binary: String {
        Bundle.main.executablePath ?? "/Applications/Plume.app/Contents/MacOS/Plume"
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: `plume` command

    static let commandLink = home.appendingPathComponent(".local/bin/plume")

    static var commandInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: commandLink.path)) == binary
    }

    static func installCommand() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: commandLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        // An old link (to another copy of the app) is replaced; a real file is left alone.
        if (try? fm.destinationOfSymbolicLink(atPath: commandLink.path)) != nil {
            try fm.removeItem(at: commandLink)
        }
        try fm.createSymbolicLink(atPath: commandLink.path, withDestinationPath: binary)
    }

    /// Is the command's folder in the terminal's PATH?
    static func commandOnPath() async -> Bool {
        let output = await shell("print -r -- $PATH")
        let directory = commandLink.deletingLastPathComponent().path
        return (output.text.split(separator: "\n").last ?? "").split(separator: ":").contains { $0 == directory }
    }

    // MARK: MCP server

    /// Configuration to paste into any MCP client.
    static var configuration: String {
        """
        {
          "mcpServers": {
            "plume": { "command": "\(binary)", "args": ["mcp"] }
          }
        }
        """
    }

    static var claudeCodeCommand: String {
        "claude mcp add --scope user plume -- \(quoted(binary)) mcp"
    }

    private static func servers(in url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root["mcpServers"] as? [String: Any] ?? [:]
    }

    static var claudeCodeConnected: Bool {
        servers(in: home.appendingPathComponent(".claude.json"))?["plume"] != nil
    }

    /// Registers the server with Claude Code, with its own command. Returns a readable error
    /// message if that isn't possible.
    static func connectClaudeCode() async -> String? {
        let found = await shell("command -v claude")
        guard found.status == 0 else { return tr("Claude Code was not found on this Mac.") }
        _ = await shell("claude mcp remove --scope user plume")
        let result = await shell(claudeCodeCommand)
        return result.status == 0 ? nil : tr("Claude Code refused the command.")
    }

    static let claudeDesktopConfig = home.appendingPathComponent(
        "Library/Application Support/Claude/claude_desktop_config.json")

    static var claudeDesktopPresent: Bool {
        FileManager.default.fileExists(atPath: claudeDesktopConfig.deletingLastPathComponent().path)
    }

    static var claudeDesktopConnected: Bool {
        guard let entry = servers(in: claudeDesktopConfig)?["plume"] as? [String: Any] else { return false }
        return entry["command"] as? String == binary
    }

    /// Adds Plume to Claude Desktop's configuration, without touching the rest of the file.
    /// The previous version is kept alongside, as `.avant-plume`.
    static func connectClaudeDesktop() throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: claudeDesktopConfig) {
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = existing
            let backup = claudeDesktopConfig.appendingPathExtension("avant-plume")
            if !fm.fileExists(atPath: backup.path) { try data.write(to: backup) }
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["plume"] = ["command": binary, "args": ["mcp"]]
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeDesktopConfig, options: .atomic)
    }

    // MARK: Tools

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a command in the user's shell, with their usual PATH (an app
    /// launched from the Finder only gets a minimal one).
    private static func shell(_ command: String) async -> (status: Int32, text: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return (-1, "")
            }
            // A shell waiting for input must not block the app.
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                if process.isRunning { process.terminate() }
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
