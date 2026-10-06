import Foundation
import PlumeKit
import Testing

/// Le serveur MCP (`plume mcp`), comme le voit un client : des requêtes JSON-RPC sur l'entrée
/// standard, une réponse par ligne. Jamais `listen` ni `summarize_transcript`, qui pilotent
/// l'app ou l'IA locale : le lanceur les refuse.
@Suite("Serveur MCP")
struct MCPServerTests {
    static let readTools = ["get_latest_transcript", "list_transcripts", "get_transcript", "search_transcripts"]

    /// Envoie les requêtes, puis la fin de l'entrée ; rend les réponses par identifiant.
    private func exchange(_ requests: [[String: Any]], library: URL) async throws -> (responses: [Int: [String: Any]], count: Int) {
        let input = try requests.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"
        let output = try await PlumeBinary.run(["mcp"], library: library, input: input)
        #expect(output.status == 0, "\(output.stderr)")
        let lines = output.stdout.split(separator: "\n").map(String.init)
        var responses: [Int: [String: Any]] = [:]
        for line in lines {
            let response = try #require((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], "pas un objet JSON : \(line)")
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

    @Test func sePrésenteEtNeRépondPasAuxNotifications() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, count) = try await exchange([
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2024-11-05"]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "ping"],
        ], library: library.root)
        // Trois messages, deux réponses : la notification n'en a pas.
        #expect(count == 2)
        let result = responses[1]?["result"] as? [String: Any]
        #expect((result?["serverInfo"] as? [String: Any])?["name"] as? String == "plume")
        // Une autre version que celle par défaut du serveur : sinon un écho cassé passerait inaperçu.
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
        #expect(responses[2]?["result"] != nil)
    }

    @Test func listeSesOutilsAvecLeurSchéma() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, _) = try await exchange([["jsonrpc": "2.0", "id": 1, "method": "tools/list"]], library: library.root)
        let tools = try #require((responses[1]?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names.isSuperset(of: Self.readTools + ["listen", "summarize_transcript"]), "outils : \(names.sorted())")
        for tool in tools {
            #expect(tool["inputSchema"] is [String: Any], "\(tool["name"] ?? "?") sans schéma")
        }
    }

    @Test func lesOutilsDeLectureRendentLaBibliothèque() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, _) = try await exchange([
            call(1, "get_latest_transcript"),
            call(2, "get_latest_transcript", ["mode": "reunion"]),
            call(3, "get_transcript", ["id": library.dictation.id]),
            call(4, "list_transcripts", ["limit": 2]),
            call(5, "search_transcripts", ["query": "budget"]),
            call(6, "get_transcript", ["id": "1999-01-01_00-00-00"]),
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
        // Un identifiant inconnu ne rend aucune des transcriptions.
        let unknown = text(of: responses[6])
        #expect(!unknown.isEmpty)
        for sentence in ["Message vocal : rappelle-moi demain.", "On commence par le budget.", "Le rapport trimestriel est prêt."] {
            #expect(!unknown.contains(sentence))
        }
    }

    @Test func unOutilOuUneMéthodeInconnusSontSignalés() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let (responses, _) = try await exchange([
            call(1, "outil_inconnu"),
            ["jsonrpc": "2.0", "id": 2, "method": "methode/inconnue"],
        ], library: library.root)
        // Outil inconnu : signalé dans le résultat (`isError`, ce que fait le serveur aujourd'hui)
        // ou comme erreur du protocole (-32602, ce que demande MCP 2025-06-18) ; les deux conviennent.
        let toolResult = responses[1]?["result"] as? [String: Any]
        let toolError = responses[1]?["error"] as? [String: Any]
        #expect(toolResult?["isError"] as? Bool == true || toolError?["code"] as? Int == -32602)
        #expect((responses[2]?["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}
