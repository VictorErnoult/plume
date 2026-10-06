import Foundation
import Testing
@testable import PlumeKit

/// Les fichiers que la bibliothèque tient à jour pour les IA (`LISEZMOI.md`) : `index.jsonl`,
/// une ligne par transcription, et `dernier.md`, la plus récente.
@Suite("Fichiers de la bibliothèque pour les IA")
struct LibraryFilesTests {
    static let indexKeys: Set<String> = ["id", "date", "mode", "appareil", "duree_s", "interlocuteurs", "fichier", "apercu"]

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Trois transcriptions inventées, de la plus ancienne à la plus récente, enregistrées dans
    /// l'ordre inverse : l'index et `dernier.md` suivent la date, pas l'ordre d'enregistrement
    /// (renommer un interlocuteur réenregistre une transcription ancienne).
    private func makeLibrary() throws -> (root: URL, transcripts: [Transcript]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
        let transcripts = [
            Transcript(
                id: "2026-10-02_09-15-00", createdAt: date("2026-10-02T07:15:00Z"), mode: .dictation, duration: 4.2,
                engine: "parakeet-ultra", text: "Le rapport est prêt.", rawText: "le rapport est prêt", title: "Rapport"),
            Transcript(
                id: "2026-10-02_14-31-05", createdAt: date("2026-10-02T12:31:05Z"), mode: .meeting, duration: 95,
                engine: "parakeet-ultra", text: "**Moi** : Bonjour.", rawText: "bonjour",
                segments: [Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 1, text: "Bonjour.")],
                speakers: ["Moi"]),
            Transcript(
                id: "2026-10-03_08-00-00", createdAt: date("2026-10-03T06:00:00Z"), mode: .imported, duration: 62,
                engine: "parakeet-v3", text: "Message vocal.", rawText: "message vocal"),
        ]
        let store = TranscriptStore(root: root)
        for transcript in transcripts.reversed() { try store.save(transcript) }
        return (root, transcripts)
    }

    @Test func chaqueLigneDeLIndexDécritUneTranscription() throws {
        let (root, transcripts) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = try String(contentsOf: root.appendingPathComponent("index.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines.count == transcripts.count)
        for (line, transcript) in zip(lines, transcripts) {
            let entry = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(Self.indexKeys.isSubset(of: entry.keys), "clés : \(entry.keys.sorted())")
            #expect(entry["id"] as? String == transcript.id)
            #expect((entry["titre"] as? String) == transcript.title)
            let file = try #require(entry["fichier"] as? String)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path, isDirectory: &isDirectory)
            #expect(exists && !isDirectory.boolValue, "\(file) manque")
            #expect((file as NSString).lastPathComponent.hasPrefix(transcript.id + "_"), "\(file) n'est pas \(transcript.id)")
        }
    }

    @Test func dernierMdEstLaTranscriptionLaPlusRécente() throws {
        let (root, transcripts) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let latest = try String(contentsOf: root.appendingPathComponent("dernier.md"), encoding: .utf8)
        #expect(latest == TranscriptStore.markdown(for: transcripts.last!))
    }
}
