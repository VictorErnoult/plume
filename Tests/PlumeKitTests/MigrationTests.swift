import Foundation
import Testing
@testable import PlumeKit

/// Files written by 1.0.1 and earlier under French names move to their English name once.
@Suite("Migration")
struct MigrationTests {
    private let fm = FileManager.default

    private func temporaryFolder() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test func resolveMovesTheOldFileOnce() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("remplacements.json")
        let new = root.appendingPathComponent("replacements.json")
        try write("old", to: old)
        #expect(Migration.resolve(old: old, new: new) == new)
        #expect(read(new) == "old")
        #expect(!fm.fileExists(atPath: old.path))
    }

    @Test func resolveLeavesBothAloneWhenTheNewOneExists() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("remplacements.json")
        let new = root.appendingPathComponent("replacements.json")
        try write("old", to: old)
        try write("new", to: new)
        #expect(Migration.resolve(old: old, new: new) == new)
        #expect(read(old) == "old")
        #expect(read(new) == "new")
    }

    @Test func resolveCreatesNothingWhenNeitherExists() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("remplacements.json")
        let new = root.appendingPathComponent("replacements.json")
        #expect(Migration.resolve(old: old, new: new) == new)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(!fm.fileExists(atPath: new.path))
    }

    @Test func resolveMovesAFolderWithItsContent() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("Transcriptions", isDirectory: true)
        let new = root.appendingPathComponent("Transcripts", isDirectory: true)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try write("note", to: old.appendingPathComponent("a.md"))
        #expect(Migration.resolve(old: old, new: new) == new)
        #expect(read(new.appendingPathComponent("a.md")) == "note")
        #expect(!fm.fileExists(atPath: old.path))
    }

    @Test func resolveKeepsReadingTheOldFileWhenTheMoveFails() throws {
        let root = try temporaryFolder()
        let old = root.appendingPathComponent("remplacements.json")
        let new = root.appendingPathComponent("replacements.json")
        try write("old", to: old)
        // Read-only parent: the rename fails. Restore before cleanup.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? fm.removeItem(at: root)
        }
        #expect(Migration.resolve(old: old, new: new) == old)
        #expect(read(old) == "old")
        #expect(!fm.fileExists(atPath: new.path))
    }

    @Test func mergeMovesEntriesAndRemovesTheEmptyOldFolder() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let new = root.appendingPathComponent("new", isDirectory: true)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try write("a", to: old.appendingPathComponent("a.md"))
        try write("b", to: old.appendingPathComponent("b.md"))
        try write("c", to: new.appendingPathComponent("c.md"))
        Migration.merge(folder: old, into: new)
        #expect(read(new.appendingPathComponent("a.md")) == "a")
        #expect(read(new.appendingPathComponent("b.md")) == "b")
        #expect(read(new.appendingPathComponent("c.md")) == "c")
        #expect(!fm.fileExists(atPath: old.path))
    }

    @Test func mergeSkipsANameAlreadyInTheNewFolder() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let new = root.appendingPathComponent("new", isDirectory: true)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try write("from old", to: old.appendingPathComponent("a.md"))
        try write("from new", to: new.appendingPathComponent("a.md"))
        Migration.merge(folder: old, into: new)
        #expect(read(old.appendingPathComponent("a.md")) == "from old")
        #expect(read(new.appendingPathComponent("a.md")) == "from new")
    }

    @Test func mergeRemovesAnOldFolderHoldingOnlyDSStore() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let new = root.appendingPathComponent("new", isDirectory: true)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try write("junk", to: old.appendingPathComponent(".DS_Store"))
        Migration.merge(folder: old, into: new)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(!fm.fileExists(atPath: new.appendingPathComponent(".DS_Store").path))
    }

    @Test func mergeKeepsANonEmptyOldFolder() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let new = root.appendingPathComponent("new", isDirectory: true)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try write("from old", to: old.appendingPathComponent("a.md"))
        try write("from new", to: new.appendingPathComponent("a.md"))
        Migration.merge(folder: old, into: new)
        #expect(fm.fileExists(atPath: old.path))
    }

    @Test func mergeIgnoresAMissingOldFolder() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let new = root.appendingPathComponent("new", isDirectory: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        Migration.merge(folder: old, into: new)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(try fm.contentsOfDirectory(atPath: new.path).isEmpty)
    }

    /// A 1.0.1 library keeps its cancelled recordings in `.annules`; an older version run
    /// after the upgrade may recreate it. Either way they stay listed (and purged).
    @Test func cancelledStoreMovesTheOldFolderThenMergesALateOne() throws {
        let root = try temporaryFolder()
        defer { try? fm.removeItem(at: root) }
        let library = root.appendingPathComponent("library", isDirectory: true)
        try fm.copyItem(at: Fixtures.root.appendingPathComponent("1.0.1/library"), to: library)
        let old = library.appendingPathComponent(".annules", isDirectory: true)

        let store = CancelledStore(library: library)
        #expect(store.root.lastPathComponent == ".cancelled")
        #expect(store.list().map(\.id) == ["2026-10-03_10-00-00"])
        #expect(!fm.fileExists(atPath: old.path))

        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        let late = CancelledRecording(
            id: "2026-10-04_09-00-00", createdAt: FixtureSamples.date("2026-10-04T07:00:00Z"),
            cancelledAt: FixtureSamples.date("2026-10-04T07:01:00Z"), mode: .dictation, duration: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(late).write(to: old.appendingPathComponent(late.id + ".json"))

        #expect(Set(CancelledStore(library: library).list().map(\.id)) == ["2026-10-03_10-00-00", late.id])
        #expect(!fm.fileExists(atPath: old.path))
    }
}
