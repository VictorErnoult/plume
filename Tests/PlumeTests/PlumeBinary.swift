import Foundation
import PlumeKit
import Testing

/// Le binaire de l'app, construit avec les tests, lancé comme le ferait un script ou une IA.
/// Seulement des commandes de lecture : sans argument, ou avec une commande inconnue, il
/// lancerait l'app (fenêtre, modèle, raccourcis) ; d'autres pilotent l'app ou le clavier.
/// Avec `mcp`, les outils `listen` et `summarize_transcript` sont refusés eux aussi.
enum PlumeBinary {
    static let readCommands: Set<String> = ["path", "last", "list", "show", "search", "export", "mcp"]

    struct Output {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    struct Refused: Error, CustomStringConvertible {
        var arguments: [String]
        var description: String { "commande refusée dans les tests : \(arguments)" }
    }

    private final class Marker {}

    /// SwiftPM range le binaire de l'app à côté du paquet de tests, avec les deux systèmes de
    /// construction (`.build/out/Products/Debug`, `.build/arm64-apple-macosx/debug`).
    static var url: URL {
        Bundle(for: Marker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Plume")
    }

    /// Refuse, sans rien lancer, une commande qui ouvrirait ou piloterait l'app : les tests du
    /// lanceur passent par ici, pour qu'une vérification cassée ne lance jamais rien.
    static func check(_ arguments: [String], input: String = "") throws {
        guard let command = arguments.first, readCommands.contains(command), !arguments.contains("-o") else {
            throw Refused(arguments: arguments)
        }
        // Sur le serveur MCP, `listen` pilote l'app et `summarize_transcript` l'IA locale. Découpé
        // aux octets de fin de ligne, comme le serveur lit : un « \r\n » ne doit rien cacher.
        if command == "mcp" {
            for line in input.utf8.split(separator: UInt8(ascii: "\n")) {
                let request = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                let tool = (request?["params"] as? [String: Any])?["name"] as? String
                if tool == "listen" || tool == "summarize_transcript" { throw Refused(arguments: arguments + [tool!]) }
            }
        }
    }

    /// Lance le binaire sur `library`, dans un environnement vierge : réglages neufs jamais
    /// écrits, canal et dossier de support à part, sans île ni collage, en UTC. Tué après 30 s.
    static func run(_ arguments: [String], library: URL, input: String = "") async throws -> Output {
        try check(arguments, input: input)
        #expect(FileManager.default.isExecutableFile(atPath: url.path), "binaire introuvable : \(url.path)")
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("plume-binary-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        // Fichiers plutôt que tubes : une sortie abondante ne peut pas bloquer le processus.
        let stdin = work.appendingPathComponent("stdin"), stdout = work.appendingPathComponent("stdout")
        let stderr = work.appendingPathComponent("stderr")
        try Data(input.utf8).write(to: stdin)
        fm.createFile(atPath: stdout.path, contents: nil)
        fm.createFile(atPath: stderr.path, contents: nil)

        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.environment = [
            "PLUME_LIBRARY": library.path,
            "PLUME_SUPPORT": work.appendingPathComponent("support").path,
            // Un jeu de réglages jamais écrit : seules les valeurs par défaut, aucun fichier créé.
            "PLUME_DEFAULTS": "tests-\(UUID().uuidString)",
            "PLUME_CHANNEL": "tests",
            "PLUME_HEADLESS": "1",
            "PLUME_NO_PASTE": "1",
            "TZ": "UTC",
            // Le vrai dossier personnel : Foundation ne lit pas $HOME pour le trouver, ce n'est
            // donc pas une isolation, juste un environnement normal.
            "HOME": NSHomeDirectory(),
        ]
        process.standardInput = try FileHandle(forReadingFrom: stdin)
        process.standardOutput = try FileHandle(forWritingTo: stdout)
        process.standardError = try FileHandle(forWritingTo: stderr)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak process] in
                if let process, process.isRunning { process.terminate() }
            }
        }
        if process.terminationReason == .uncaughtSignal {
            Issue.record("\(arguments) : arrêté au bout de 30 s, ou tué par un signal")
        }
        return Output(
            status: process.terminationStatus,
            stdout: (try? String(contentsOf: stdout, encoding: .utf8)) ?? "",
            stderr: (try? String(contentsOf: stderr, encoding: .utf8)) ?? "")
    }
}

/// Une bibliothèque inventée : une dictée, une réunion, un import, enregistrés par l'app.
struct SampleLibrary {
    let root: URL
    let dictation: Transcript
    let meeting: Transcript
    let imported: Transcript

    static func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    static func make() throws -> SampleLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-library-\(UUID().uuidString)", isDirectory: true)
        let dictation = Transcript(
            id: "2026-10-02_09-15-00", createdAt: date("2026-10-02T07:15:00Z"), mode: .dictation, duration: 4.2,
            engine: "parakeet-ultra", text: "Le rapport trimestriel est prêt.", rawText: "le rapport trimestriel est prêt",
            app: "Notes")
        let meeting = Transcript(
            id: "2026-10-02_14-31-05", createdAt: date("2026-10-02T12:31:05Z"), mode: .meeting, duration: 95,
            engine: "parakeet-ultra", text: "**Moi** : On commence par le budget.\n\n**Inès** : D'accord.",
            rawText: "on commence par le budget d'accord",
            segments: [
                Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 3, text: "On commence par le budget."),
                Segment(id: 1, speaker: "Inès", channel: .system, start: 3.5, end: 5, text: "D'accord."),
            ],
            speakers: ["Moi", "Inès"], title: "Point budget")
        let imported = Transcript(
            id: "2026-10-03_08-00-00", createdAt: date("2026-10-03T06:00:00Z"), mode: .imported, duration: 62,
            engine: "parakeet-v3", text: "Message vocal : rappelle-moi demain.", rawText: "message vocal rappelle-moi demain")
        let store = TranscriptStore(root: root)
        for transcript in [dictation, meeting, imported] { try store.save(transcript) }
        return SampleLibrary(root: root, dictation: dictation, meeting: meeting, imported: imported)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
