// Tests/PlumeKitTests/ReadAloud/ReadAloudEvalTests.swift
import Foundation
import JavaScriptCore
import Testing
@testable import PlumeKit

@Suite("Read-aloud eval")
struct ReadAloudEvalTests {
    @Test func everyFileGetsEveryEngine() async throws {
        let a = FakeSummaryService(pieces: ["Summary A."])
        let b = FakeSummaryService(pieces: ["<|channel>thought x<channel|>"])  // b (Gemma's markers) fails: empty summary
        let results = await ReadAloudEval.run(
            files: [("mail.txt", "A first text to summarize here."), ("article.txt", "Another text to summarize.")],
            engines: [(SummaryEngineCatalog.qwen35_4b, a), (SummaryEngineCatalog.gemma4_e2b, b)],
            options: SummaryOptions(length: .automatic, language: .sameAsText), interface: .english,
            created: Date(timeIntervalSince1970: 0), progress: { _ in })
        #expect(results.engines.map(\.id) == ["qwen3.5-4b-q4km", "gemma4-e2b-q4"])
        #expect(results.items.map(\.file) == ["mail.txt", "article.txt"])
        #expect(results.items.map(\.text) == ["A first text to summarize here.", "Another text to summarize."])
        for item in results.items {
            #expect(item.results["qwen3.5-4b-q4km"]?.summary == "Summary A.")
            #expect(item.results["gemma4-e2b-q4"]?.error != nil)
        }
        #expect(results.items[0].results["qwen3.5-4b-q4km"]?.cold == true)
        #expect(results.items[1].results["qwen3.5-4b-q4km"]?.cold == false)
        let data = try JSONEncoder().encode(results)
        #expect(try JSONDecoder().decode(ReadAloudEval.Results.self, from: data) == results)
    }

    /// The judge page's verdict math, run with the page's own script.
    @Test func judgeSummaryCountsPerEngine() throws {
        let script = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("bench/read-aloud-eval/judge.js"),
            encoding: .utf8)
        let context = try #require(JSContext())
        context.evaluateScript(script)
        let results = #"{"engines":[{"id":"q"},{"id":"g"}],"items":[{"file":"a","words":100,"results":{"q":{"totalSeconds":2,"firstSentenceSeconds":1},"g":{"totalSeconds":1,"firstSentenceSeconds":0.5}}},{"file":"b","words":2000,"results":{"q":{"totalSeconds":4,"firstSentenceSeconds":3},"g":{"totalSeconds":2,"firstSentenceSeconds":1}}}]}"#
        let verdicts = #"{"a":{"order":["g","q"],"A":{"mainPoint":true,"nothingInvented":true,"rightLanguage":true,"rightLength":false},"B":{"mainPoint":true,"nothingInvented":false,"rightLanguage":true,"rightLength":true},"preference":"A"},"b":{"order":["q","g"],"A":{"mainPoint":true,"nothingInvented":true,"rightLanguage":true,"rightLength":true},"B":{"mainPoint":false,"nothingInvented":true,"rightLanguage":true,"rightLength":true},"preference":"equal"}}"#
        let summary = try #require(context.evaluateScript("JSON.stringify(PlumeJudge.summarize(\(results), \(verdicts)))")?.toString())
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(summary.utf8)) as? [String: Any])
        let engines = try #require(parsed["engines"] as? [String: [String: Any]])
        let q = try #require(engines["q"]?["all"] as? [String: Double])
        let g = try #require(engines["g"]?["all"] as? [String: Double])
        #expect(q["mainPoint"] == 1.0 && q["nothingInvented"] == 0.5)
        #expect(g["mainPoint"] == 0.5 && g["rightLength"] == 0.5)
        #expect(engines["g"]?["preferred"] as? Int == 1)
        #expect(engines["q"]?["preferred"] as? Int == 0)
        #expect(parsed["ties"] as? Int == 1)
        #expect(engines["q"]?["medianTotalSeconds"] as? Double == 3)
    }
}
