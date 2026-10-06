import Foundation
import PlumeKit
import Testing

/// The MCP server (`plume mcp`), as a client sees it: JSON-RPC requests on standard
/// input, one response per line. Never `listen` or `summarize_transcript`, which drive
/// the app or the local AI: the launcher refuses them.
@Suite("MCP server")
struct MCPServerTests {
    static let readTools = ["get_latest_transcript", "list_transcripts", "get_transcript", "search_transcripts"]

    /// Sends the requests, then end of input; returns the responses by identifier.
    private func exchange(_ requests: [[String: Any]], library: URL) async throws -> (responses: [Int: [String: Any]], count: Int) {
        let input = try requests.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"
        let output = try await PlumeBinary.run(["mcp"], library: library, input: input)
        #expect(output.status == 0, "\(output.stderr)")
        let lines = output.stdout.split(separator: "\n").map(String.init)
        var responses: [Int: [String: Any]] = [:]
        for line in lines {
            let response = try #require((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], "not a JSON object: \(line)")
            #expect(response["jsonrpc"] as? String == "2.0")
            if let id = response["id"] as? Int { responses[id] = response }
        }
        return (responses, lines.count)
    }

    private func call(_ id: Int, _ tool: String, _ arguments: [String: Any] = [:]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": tool, "arguments": arguments]]
    }

    private func text(of response: [String: Any]?) -> String {
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    @Test func introducesItselfAndDoesNotAnswerNotifications() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, count) = try await exchange([
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2024-11-05"]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "ping"],
        ], library: library.root)
        // Three messages, two responses: the notification has none.
        #expect(count == 2)
        let result = responses[1]?["result"] as? [String: Any]
        #expect((result?["serverInfo"] as? [String: Any])?["name"] as? String == "plume")
        // A version other than the server's default: otherwise a broken echo would go unnoticed.
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
        #expect(responses[2]?["result"] != nil)
    }

    @Test func listsItsToolsWithTheirSchema() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, _) = try await exchange([["jsonrpc": "2.0", "id": 1, "method": "tools/list"]], library: library.root)
        let tools = try #require((responses[1]?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names.isSuperset(of: Self.readTools + ["listen", "summarize_transcript"]), "tools: \(names.sorted())")
        for tool in tools {
            #expect(tool["inputSchema"] is [String: Any], "\(tool["name"] ?? "?") has no schema")
        }
    }

    @Test func readToolsReturnTheLibrary() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, _) = try await exchange([
            call(1, "get_latest_transcript"),
            call(2, "get_latest_transcript", ["mode": "reunion"]),
            call(3, "get_transcript", ["id": library.dictation.id]),
            call(4, "list_transcripts", ["limit": 2]),
            call(5, "search_transcripts", ["query": "budget"]),
            call(6, "get_transcript", ["id": "1999-01-01_00-00-00"]),
            call(7, "list_transcripts", ["mode": "reunion"]),
            call(8, "list_transcripts", ["mode": "meeting"]),
            call(9, "list_transcripts", ["mode": "dictation"]),
            call(10, "list_transcripts", ["mode": "imported"]),
        ], library: library.root)
        #expect(text(of: responses[1]).contains("Message vocal : rappelle-moi demain."))
        #expect(text(of: responses[2]).contains("On commence par le budget."))
        #expect(text(of: responses[3]).contains("Le rapport trimestriel est prêt."))
        let listed = text(of: responses[4])
        #expect(listed.contains(library.imported.id))
        #expect(listed.contains(library.meeting.id))
        #expect(!listed.contains(library.dictation.id))
        let found = text(of: responses[5])
        #expect(found.contains(library.meeting.id))
        #expect(!found.contains(library.dictation.id) && !found.contains(library.imported.id))
        // An unknown identifier returns none of the transcripts.
        let unknown = text(of: responses[6])
        #expect(!unknown.isEmpty)
        for sentence in ["Message vocal : rappelle-moi demain.", "On commence par le budget.", "Le rapport trimestriel est prêt."] {
            #expect(!unknown.contains(sentence))
        }
        // The English mode names filter like the French slugs.
        let meetings = text(of: responses[7])
        #expect(meetings.contains(library.meeting.id) && !meetings.contains(library.dictation.id))
        #expect(text(of: responses[8]) == meetings)
        #expect(text(of: responses[9]).contains(library.dictation.id) && !text(of: responses[9]).contains(library.meeting.id))
        #expect(text(of: responses[10]).contains(library.imported.id) && !text(of: responses[10]).contains(library.meeting.id))
    }

    @Test func anUnknownToolOrMethodIsReported() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, _) = try await exchange([
            call(1, "outil_inconnu"),
            ["jsonrpc": "2.0", "id": 2, "method": "methode/inconnue"],
        ], library: library.root)
        // Unknown tool: reported in the result (`isError`, what the server does today)
        // or as a protocol error (-32602, what MCP 2025-06-18 asks for); both are fine.
        let toolResult = responses[1]?["result"] as? [String: Any]
        let toolError = responses[1]?["error"] as? [String: Any]
        #expect(toolResult?["isError"] as? Bool == true || toolError?["code"] as? Int == -32602)
        #expect((responses[2]?["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}
