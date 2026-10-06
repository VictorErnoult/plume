import Foundation
import Testing
@testable import PlumeKit

/// The files the library keeps up to date for AIs (`README.md`): `index.jsonl`,
/// one line per transcript, and `latest.md` (plus `dernier.md`, its deprecated copy), the most recent.
@Suite("Library files for AIs")
struct LibraryFilesTests {
    static let indexKeys: Set<String> = ["id", "date", "mode", "appareil", "duree_s", "interlocuteurs", "fichier", "apercu"]

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Three invented transcripts, oldest to newest, saved in reverse order: the index and
    /// `latest.md` follow the date, not the save order (renaming a speaker re-saves an old
    /// transcript).
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

    @Test func eachIndexLineDescribesATranscript() throws {
        let (root, transcripts) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = try String(contentsOf: root.appendingPathComponent("index.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines.count == transcripts.count)
        for (line, transcript) in zip(lines, transcripts) {
            let entry = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(Self.indexKeys.isSubset(of: entry.keys), "keys: \(entry.keys.sorted())")
            #expect(entry["id"] as? String == transcript.id)
            #expect((entry["titre"] as? String) == transcript.title)
            let file = try #require(entry["fichier"] as? String)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path, isDirectory: &isDirectory)
            #expect(exists && !isDirectory.boolValue, "\(file) is missing")
            #expect((file as NSString).lastPathComponent.hasPrefix(transcript.id + "_"), "\(file) is not \(transcript.id)")
        }
    }

    private func read(_ root: URL, _ name: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    private func exists(_ root: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func latestMdIsTheMostRecentTranscriptAndDernierMdIsItsCopy() throws {
        let (root, transcripts) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = TranscriptStore.markdown(for: transcripts.last!)
        #expect(read(root, "latest.md") == expected)
        #expect(read(root, "dernier.md") == expected)
    }

    @Test func aStaleDernierMdIsReplaced() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "an older copy".write(to: root.appendingPathComponent("dernier.md"), atomically: true, encoding: .utf8)
        let transcript = Transcript(
            id: "2026-10-02_09-15-00", createdAt: date("2026-10-02T07:15:00Z"), mode: .dictation, duration: 4.2,
            engine: "parakeet-ultra", text: "Le rapport est prêt.", rawText: "le rapport est prêt")
        try TranscriptStore(root: root).save(transcript)
        #expect(read(root, "dernier.md") == TranscriptStore.markdown(for: transcript))
        #expect(read(root, "latest.md") == read(root, "dernier.md"))
    }

    @Test func aLibraryWithoutTranscriptHasNeitherLatestFile() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "stale".write(to: root.appendingPathComponent("dernier.md"), atomically: true, encoding: .utf8)
        TranscriptStore(root: root).prepare()
        #expect(!exists(root, "latest.md"))
        #expect(!exists(root, "dernier.md"))
        #expect(read(root, "README.md") == TranscriptStore.readme)
    }

    @Test func prepareCreatesLatestMdForAnUpgradedLibrary() throws {
        let (root, transcripts) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        // What 1.0.1 left: no latest.md, no README.md.
        try FileManager.default.removeItem(at: root.appendingPathComponent("latest.md"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("README.md"))
        TranscriptStore(root: root).prepare()
        #expect(read(root, "latest.md") == TranscriptStore.markdown(for: transcripts.last!))
        #expect(read(root, "README.md") == TranscriptStore.readme)
    }

    @Test func stockLisezmoiIsRemovedOnceReadmeIsWritten() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try TranscriptStore.legacyReadme.write(to: root.appendingPathComponent("LISEZMOI.md"), atomically: true, encoding: .utf8)
        TranscriptStore(root: root).prepare()
        #expect(read(root, "README.md") == TranscriptStore.readme)
        #expect(!exists(root, "LISEZMOI.md"))
    }

    @Test func anEditedLisezmoiStays() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let edited = TranscriptStore.legacyReadme + "\nMy own note.\n"
        try edited.write(to: root.appendingPathComponent("LISEZMOI.md"), atomically: true, encoding: .utf8)
        TranscriptStore(root: root).prepare()
        #expect(read(root, "LISEZMOI.md") == edited)
        #expect(read(root, "README.md") == TranscriptStore.readme)
    }

    @Test func aUsersOwnReadmeIsLeftAloneAndLisezmoiStays() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# My project".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try TranscriptStore.legacyReadme.write(to: root.appendingPathComponent("LISEZMOI.md"), atomically: true, encoding: .utf8)
        TranscriptStore(root: root).prepare()
        #expect(read(root, "README.md") == "# My project")
        #expect(read(root, "LISEZMOI.md") == TranscriptStore.legacyReadme)
    }

    /// The guide names every file and index key an outside reader relies on.
    @Test func theGuideNamesTheFilesAndKeys() {
        let guide = TranscriptStore.readme
        for name in ["latest.md", "dernier.md", "deprecated", "index.jsonl", "Moi", "Me"] + Array(Self.indexKeys) + ["titre"] {
            #expect(guide.contains(name), "\(name) is missing from the guide")
        }
    }
}
