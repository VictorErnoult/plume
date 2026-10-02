import AppKit
import Foundation

/// Ce qui relie Plume au terminal et aux assistants : la commande `plume`, et la déclaration
/// du serveur MCP auprès de Claude Code et de Claude Desktop.
enum Integrations {
    /// Le binaire de l'app : c'est lui que lancent la commande et le serveur MCP.
    static var binary: String {
        Bundle.main.executablePath ?? "/Applications/Plume.app/Contents/MacOS/Plume"
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: Commande `plume`

    static let commandLink = home.appendingPathComponent(".local/bin/plume")

    static var commandInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: commandLink.path)) == binary
    }

    static func installCommand() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: commandLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Un ancien lien (vers une autre copie de l'app) est remplacé ; un vrai fichier est laissé.
        if (try? fm.destinationOfSymbolicLink(atPath: commandLink.path)) != nil {
            try fm.removeItem(at: commandLink)
        }
        try fm.createSymbolicLink(atPath: commandLink.path, withDestinationPath: binary)
    }

    /// Le dossier de la commande figure-t-il dans le PATH du terminal ?
    static func commandOnPath() async -> Bool {
        let output = await shell("print -r -- $PATH")
        let directory = commandLink.deletingLastPathComponent().path
        return (output.text.split(separator: "\n").last ?? "").split(separator: ":").contains { $0 == directory }
    }

    // MARK: Serveur MCP

    /// Configuration à coller dans un client MCP quelconque.
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

    /// Déclare le serveur auprès de Claude Code, avec sa propre commande. Renvoie un message
    /// d'erreur lisible si ce n'est pas possible.
    static func connectClaudeCode() async -> String? {
        let found = await shell("command -v claude")
        guard found.status == 0 else { return "Claude Code n'a pas été trouvé sur ce Mac." }
        _ = await shell("claude mcp remove --scope user plume")
        let result = await shell(claudeCodeCommand)
        return result.status == 0 ? nil : "Claude Code a refusé la commande."
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

    /// Ajoute Plume à la configuration de Claude Desktop, sans toucher au reste du fichier.
    /// L'ancienne version est gardée à côté, en `.avant-plume`.
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

    // MARK: Outils

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Lance une commande dans le shell de l'utilisateur, avec son PATH habituel (une app
    /// lancée depuis le Finder n'en reçoit qu'un minimal).
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
            // Un shell qui attendrait une saisie ne doit pas bloquer l'app.
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                if process.isRunning { process.terminate() }
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
