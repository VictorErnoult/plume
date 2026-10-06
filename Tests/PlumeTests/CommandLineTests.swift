import Foundation
import PlumeKit
import Testing

/// What the command line gives to scripts and AIs (`plume last --json`…), with the real
/// binary. We check that the keys are present, not that they are exclusive: adding more is allowed.
@Suite("Command line")
struct CommandLineTests {
    static let summaryKeys: Set<String> = ["id", "date", "mode", "duree_s", "interlocuteurs", "apercu"]

    private func decodeTranscript(_ text: String) throws -> Transcript {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Transcript.self, from: Data(text.utf8))
    }

    private func summaries(_ text: String) throws -> [[String: Any]] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    @Test func pathGivesTheLibraryFolder() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let output = try await PlumeBinary.run(["path"], library: library.root)
        #expect(output.status == 0)
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == library.root.path)
    }

    @Test func lastGivesTheLatestTranscriptAsSaved() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let output = try await PlumeBinary.run(["last", "--json"], library: library.root)
        #expect(output.status == 0)
        #expect(try decodeTranscript(output.stdout) == library.imported)
    }

    @Test func lastIsLimitedToTheRequestedMode() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let output = try await PlumeBinary.run(["last", "--mode", "reunion", "--json"], library: library.root)
        #expect(output.status == 0)
        #expect(try decodeTranscript(output.stdout) == library.meeting)
    }

    @Test func showGivesATranscript() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let output = try await PlumeBinary.run(["show", library.dictation.id, "--json"], library: library.root)
        #expect(output.status == 0)
        #expect(try decodeTranscript(output.stdout) == library.dictation)
    }

    @Test func listGivesSummariesNewestFirst() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let all = try summaries(try await PlumeBinary.run(["list", "--json"], library: library.root).stdout)
        #expect(all.map { $0["id"] as? String } == [library.imported.id, library.meeting.id, library.dictation.id])
        for summary in all {
            #expect(Self.summaryKeys.isSubset(of: summary.keys), "keys: \(summary.keys.sorted())")
        }
        let one = try summaries(try await PlumeBinary.run(["list", "-n", "1", "--json"], library: library.root).stdout)
        #expect(one.map { $0["id"] as? String } == [library.imported.id])
    }

    @Test func searchIgnoresAccentsAndCase() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let found = try summaries(try await PlumeBinary.run(["search", "TRIMESTRIEL", "pret", "--json"], library: library.root).stdout)
        #expect(found.map { $0["id"] as? String } == [library.dictation.id])
        #expect(Self.summaryKeys.isSubset(of: found.first.map { Set($0.keys) } ?? []))
        // The search matches substrings: "le" is also found in "rappelle".
        let all = try summaries(try await PlumeBinary.run(["search", "le", "--json"], library: library.root).stdout)
        #expect(all.map { $0["id"] as? String } == [library.imported.id, library.meeting.id, library.dictation.id])
    }

    @Test func anUnknownTranscriptExitsWithAnError() async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let output = try await PlumeBinary.run(["show", "1999-01-01_00-00-00", "--json"], library: library.root)
        #expect(output.status == 1)
        #expect(output.stdout.isEmpty)
        #expect(!output.stderr.isEmpty)
    }

    @Test func anEmptyLibraryExitsWithAnError() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("plume-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let output = try await PlumeBinary.run(["last", "--json"], library: empty)
        #expect(output.status == 1)
        #expect(output.stdout.isEmpty)
    }

    @Test(arguments: ["json", "md", "txt", "srt", "vtt"])
    func exportProducesItsFormat(format: String) async throws {
        let library = try SampleLibrary.make()
        defer { library.remove() }
        let output = try await PlumeBinary.run(["export", library.meeting.id, "--format", format], library: library.root)
        #expect(output.status == 0)
        let text = output.stdout
        switch format {
        case "json":
            #expect(try decodeTranscript(text) == library.meeting)
        case "md":
            #expect(text.hasPrefix("---\n"))
            #expect(text.contains("\nid: \(library.meeting.id)\n"))
            #expect(text.contains("D'accord."))
        case "txt":
            #expect(text.contains("On commence par le budget."))
            #expect(!text.hasPrefix("---"))
        case "srt":
            #expect(text.hasPrefix("1\n00:00:00,000 --> "))
            #expect(text.contains("\n2\n"))
        default:
            #expect(text.hasPrefix("WEBVTT"))
            #expect(text.contains(" --> "))
        }
    }

    /// The launcher refuses without launching anything: even if broken, the check would not
    /// make this test launch the app or press real keys.
    @Test func theLauncherRefusesCommandsThatWouldDriveTheApp() throws {
        for arguments in [[], ["toggle", "dictee"], ["simulate-chord"], ["--version"], ["export", "x", "-o", "/tmp/x"]] {
            #expect(throws: PlumeBinary.Refused.self) { try PlumeBinary.check(arguments) }
        }
        let listen = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"listen","arguments":{}}}"#
        let summarize = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"summarize_transcript","arguments":{"id":"x"}}}"#
        let initialize = #"{"jsonrpc":"2.0","id":3,"method":"initialize","params":{}}"#
        for input in [listen + "\n", initialize + "\r\n" + listen + "\r\n", summarize + "\n"] {
            #expect(throws: PlumeBinary.Refused.self) { try PlumeBinary.check(["mcp"], input: input) }
        }
        // What is allowed goes through.
        #expect(throws: Never.self) { try PlumeBinary.check(["list", "--json"]) }
        #expect(throws: Never.self) { try PlumeBinary.check(["mcp"], input: initialize + "\n") }
    }
}
