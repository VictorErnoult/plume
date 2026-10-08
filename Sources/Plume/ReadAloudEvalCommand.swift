// Sources/Plume/ReadAloudEvalCommand.swift
import Foundation
import PlumeKit

/// `plume read-aloud --eval <folder> --engines a,b --out results.json`.
enum ReadAloudEvalCommand {
    static func run(_ options: ReadAloudCommand.Options, folder: String, context: ReadAloudCommand.Context, emit: (String) -> Void) async throws -> Int32 {
        let directory = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".txt") }.sorted()
        let files = try names.map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
        let engines = try options.evalEngines.map { id -> (entry: SummaryEngineEntry, service: any SummaryService) in
            guard let entry = SummaryEngineCatalog.entry(id: id, in: context.catalog) else { throw ReadAloudError.unknownEngine }
            guard context.models.isInstalled(entry) else { throw ReadAloudError.engineNotInstalled }
            return (entry, LlamaSummaryService(entry: entry, modelURL: context.models.modelURL(for: entry)))
        }
        let results = await ReadAloudEval.run(
            files: files, engines: engines, options: context.options, interface: context.interface, created: Date(),
            progress: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let out = URL(fileURLWithPath: ((options.evalOut ?? "results.json") as NSString).expandingTildeInPath)
        try encoder.encode(results).write(to: out, options: .atomic)
        emit(out.path)
        return 0
    }
}
