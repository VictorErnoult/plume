import Foundation
import PlumeKit

/// Serveur MCP minimal (JSON-RPC 2.0 sur stdio) : donne à une IA un accès en lecture
/// à la bibliothèque de transcriptions.
struct MCPServer {
    let store: TranscriptStore

    func run() async {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            guard let response = await handle(message) else { continue }
            if let out = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes]),
                let text = String(data: out, encoding: .utf8)
            {
                CLI.emit(text)
            }
        }
    }

    private func handle(_ message: [String: Any]) async -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        // Les notifications n'ont pas d'identifiant et n'attendent pas de réponse.
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return result(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "plume", "version": "1.0.0"],
                "instructions":
                    "The user's local voice transcriptions (dictations, meetings with speakers, imports). "
                    + "The speaker label \"Moi\" (or \"Me\") stands for the user.",
            ])
        case "ping":
            return result(id, [String: Any]())
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let text = await call(name, arguments) else {
                return result(id, ["content": [["type": "text", "text": "Unknown tool: \(name)"]], "isError": true])
            }
            return result(id, ["content": [["type": "text", "text": text]]])
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method: \(method)"]]
        }
    }

    private func result(_ id: Any, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    private func call(_ name: String, _ args: [String: Any]) async -> String? {
        let mode = (args["mode"] as? String).flatMap(RecordingMode.init(slug:))
        switch name {
        case "get_latest_transcript":
            guard let t = store.latest(mode: mode) else { return "No transcripts." }
            return TranscriptStore.markdown(for: t)
        case "get_transcript":
            guard let id = args["id"] as? String, let t = store.load(id: id) else {
                return "Transcript not found."
            }
            return TranscriptStore.markdown(for: t)
        case "list_transcripts":
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 200)
            return summaries(store.list(limit: limit, mode: mode))
        case "search_transcripts":
            let limit = min(max(args["limit"] as? Int ?? 10, 1), 50)
            return summaries(store.search(args["query"] as? String ?? "", limit: limit))
        case "listen":
            // L'app enregistre, l'utilisateur termine avec son raccourci, le texte revient ici.
            let timeout = min(max(args["timeout"] as? Double ?? 180, 10), 900)
            guard let text = await Listener.listen(store: store, timeout: timeout) else {
                return "No dictation received: Plume may not be running, or the user said nothing before the timeout."
            }
            return text
        case "summarize_transcript":
            guard let id = args["id"] as? String, var t = store.load(id: id) else { return "Transcript not found." }
            do {
                let summary = try await LocalAI.summarize(t)
                t.summary = summary.markdown
                if t.title == nil { t.title = summary.title }
                try store.save(t)
                return "# \(summary.title)\n\n\(summary.markdown)"
            } catch {
                return "Couldn't summarize: \(error.localizedDescription)"
            }
        default:
            return nil
        }
    }

    private func summaries(_ items: [Transcript]) -> String {
        guard !items.isEmpty else { return "No results." }
        return items.map { t in
            let who = t.speakers.isEmpty ? "" : " · \(t.speakers.joined(separator: ", "))"
            return "- \(t.id) · \(t.mode.label) · \(Format.duration(t.duration))\(who)\n  \(t.preview)"
        }.joined(separator: "\n")
    }

    private static let modeProperty: [String: Any] = [
        "type": "string",
        "enum": ["dictee", "reunion", "import"],
        "description": "Filter by type: dictee (dictation), reunion (meeting, several speakers) or import (imported file).",
    ]

    private static let tools: [[String: Any]] = [
        [
            "name": "get_latest_transcript",
            "description":
                "Returns the user's most recent voice transcript (full text, with speakers for a meeting). Use it for \"my latest transcript\", \"my latest meeting\" (mode=reunion) or \"my latest dictation\" (mode=dictee).",
            "inputSchema": ["type": "object", "properties": ["mode": modeProperty]],
        ],
        [
            "name": "list_transcripts",
            "description": "Lists recent transcripts (id, type, duration, speakers, preview), newest first.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Maximum number of results (default 20)."],
                    "mode": modeProperty,
                ],
            ],
        ],
        [
            "name": "get_transcript",
            "description": "Returns the full text of a transcript from its id (e.g. 2026-10-02_14-31-05).",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "Transcript id."]],
                "required": ["id"],
            ],
        ],
        [
            "name": "search_transcripts",
            "description": "Full-text search across all transcripts (ignores case and accents; every word must appear).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Words to search for."],
                    "limit": ["type": "integer", "description": "Maximum number of results (default 10)."],
                ],
                "required": ["query"],
            ],
        ],
        [
            "name": "listen",
            "description":
                "Has the user speak: Plume opens the microphone, the user dictates a reply and finishes with their shortcut (or plume stop), and the transcribed text is returned. Use it to ask the user a question and get the answer by voice, or when they ask to reply out loud. Blocks until the dictation ends (at most timeout seconds).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "timeout": ["type": "number", "description": "Maximum wait, in seconds (default 180)."]
                ],
            ],
        ],
        [
            "name": "summarize_transcript",
            "description": "Summarizes a meeting with the Mac's local AI (key points, decisions, actions) and stores the summary in the transcript.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "Transcript id."]],
                "required": ["id"],
            ],
        ],
    ]
}
