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

    /// An eval folder with one selection, and a results file outside any repository.
    func evalSetup(selections: Bool = true) throws -> (folder: URL, options: ReadAloudCommand.Options) {
        let eval = folder.appendingPathComponent("eval")
        let selectionsFolder = eval.appendingPathComponent("selections")
        try FileManager.default.createDirectory(at: selectionsFolder, withIntermediateDirectories: true)
        if selections { try "A text.".write(to: selectionsFolder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8) }
        return (eval, ReadAloudCommand.Options(
            evalFolder: selectionsFolder.path, evalEngines: ["nope-a", "nope-b"], evalOut: eval.appendingPathComponent("results.json").path))
    }

    func evalError(_ options: ReadAloudCommand.Options) async -> [String] {
        var errors: [String] = []
        let code = await L10n.$override.withValue(.english) {
            await ReadAloudCommand.run(options, context: context(), input: "", emit: { _ in Issue.record("must not write") }, fail: { errors.append($0) })
        }
        #expect(code == 1)
        return errors
    }

    @Test func theEvalChecksItsArgumentsBeforeAnyModelLoads() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (eval, valid) = try evalSetup()
        // Valid arguments get as far as the engine lookup (the catalog has no "nope-a"), which proves the checks passed.
        #expect(await evalError(valid) == [ReadAloudError.unknownEngine.localizedDescription])
        for engines in [["qwen3.5-4b-q4km"], ["a", "a"], ["a", "b", "c"], []] {
            var options = valid
            options.evalEngines = engines
            #expect(await evalError(options) == [ReadAloudError.evalNeedsTwoEngines.localizedDescription])
        }
        var noOut = valid
        noOut.evalOut = nil
        #expect(await evalError(noOut) == [ReadAloudError.evalOutRequired.localizedDescription])
        var empty = valid
        empty.evalFolder = eval.path
        #expect(await evalError(empty) == [ReadAloudError.evalNoSelections.localizedDescription])
        var missing = valid
        missing.evalFolder = eval.appendingPathComponent("nothing-here").path
        #expect(await evalError(missing) == [ReadAloudError.evalNoSelections.localizedDescription])
    }

    @Test func theEvalRefusesAResultsFileInsideAGitWorkTree() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (eval, valid) = try evalSetup()
        // A repository root, then a linked worktree (its .git is a file), then a folder that does not exist yet below one.
        let repository = folder.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let worktree = folder.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: elsewhere".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        for out in [repository.appendingPathComponent("results.json"), worktree.appendingPathComponent("deep/new/results.json")] {
            var options = valid
            options.evalOut = out.path
            #expect(await evalError(options) == [ReadAloudError.evalOutInsideRepository.localizedDescription])
        }
        #expect(ReadAloudEvalCommand.isInsideGitWorkTree(repository.appendingPathComponent("a/b.json")))
        #expect(!ReadAloudEvalCommand.isInsideGitWorkTree(eval.appendingPathComponent("results.json")))
    }

    @Test func theCommandWordReachesTheCommandLine() {
        #expect(CLI.commands.contains("read-aloud"))
        #expect(CLI.handles(["plume", "read-aloud"]))
    }
}
