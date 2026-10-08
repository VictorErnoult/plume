import Foundation
import PlumeKit
import Testing
@testable import Plume

@Suite("plume read-aloud")
struct ReadAloudCommandTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")

    func context(engine: String = "") -> ReadAloudCommand.Context {
        ReadAloudCommand.Context(
            models: ReadAloudModels(directory: folder, installVoice: { _, _ in Issue.record("must not download") }),
            catalog: SummaryEngineCatalog.all, engineInUse: engine, voiceID: "supertonic3-f1", speed: 1.5,
            options: SummaryOptions(length: .automatic, language: .sameAsText), interface: .english)
    }

    @Test func parsesOptions() {
        #expect(ReadAloudCommand.parse([]) == ReadAloudCommand.Options())
        #expect(ReadAloudCommand.parse(["--summary", "--json", "--engine", "gemma4-e2b-q4"])
            == ReadAloudCommand.Options(summary: true, json: true, engineID: "gemma4-e2b-q4"))
        #expect(ReadAloudCommand.parse(["--download", "voice"]) == ReadAloudCommand.Options(download: "voice"))
        #expect(ReadAloudCommand.parse(["--eval", "/x", "--engines", "a,b", "--out", "/y.json"])
            == ReadAloudCommand.Options(evalFolder: "/x", evalEngines: ["a", "b"], evalOut: "/y.json"))
        #expect(ReadAloudCommand.parse(["--engine"]) == nil)
        #expect(ReadAloudCommand.parse(["--bogus"]) == nil)
    }

    @Test func printsTheWordForWordTextWithoutTheVoice() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines: [String] = []
        let code = await ReadAloudCommand.run(
            ReadAloudCommand.Options(textOnly: true), context: context(),
            input: "First sentence here. Second one.", emit: { lines.append($0) }, fail: { Issue.record("\($0)") })
        #expect(code == 0)
        #expect(lines == ["First sentence here.", "Second one."])
    }

    @Test func speakingWithoutTheVoiceFailsAndDownloadsNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(ReadAloudCommand.Options(), context: context(), input: "Hello there.", emit: { _ in }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        #expect(errors == [ReadAloudError.voiceNotInstalled.localizedDescription])
        try #expect(!FileManager.default.fileExists(atPath: folder.path) || FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func summarizingWithoutAModelFails() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(ReadAloudCommand.Options(summary: true, textOnly: true), context: context(engine: "qwen3.5-4b-q4km"),
                                       input: "Hello there.", emit: { _ in }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        #expect(errors == [ReadAloudError.engineNotInstalled.localizedDescription])
    }

    @Test func anUnknownEngineIsReported() async {
        var errors: [String] = []
        let code = await ReadAloudCommand.run(ReadAloudCommand.Options(summary: true, engineID: "nope"), context: context(),
                                              input: "Hello.", emit: { _ in }, fail: { errors.append($0) })
        #expect(code == 1)
        #expect(errors == [ReadAloudError.unknownEngine.localizedDescription])
    }

    @Test func theCommandWordReachesTheCommandLine() {
        #expect(CLI.commands.contains("read-aloud"))
        #expect(CLI.handles(["plume", "read-aloud"]))
    }
}
