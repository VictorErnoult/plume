import Foundation
import Testing
@testable import PlumeKit

/// Writes `Tests/Fixtures/<version>/` from `FixtureSamples`, with the app's code:
/// `FIXTURES_VERSION=1.0.1 ./scripts/test.sh --filter FixtureGenerator`. The folder of a
/// version not released yet (no `v<version>` tag) is deleted by hand, then regenerated.
@Suite("Sample generator")
struct FixtureGenerator {
    static let version = ProcessInfo.processInfo.environment["FIXTURES_VERSION"]

    @Test(.enabled(if: version != nil, "FIXTURES_VERSION=<version> to write a sample folder"))
    func writesTheSamplesOfThisVersion() throws {
        let version = try #require(Self.version)
        try #require(Fixtures.isVersion(version), "FIXTURES_VERSION must be a version number (1.0.2), not \"\(version)\"")
        let folder = Fixtures.root.appendingPathComponent(version, isDirectory: true)
        let fm = FileManager.default
        try #require(!fm.fileExists(atPath: folder.path), "Tests/Fixtures/\(version) already exists: leave it alone")
        // Written aside, then moved into place at once: an error leaves no half-written folder.
        let draft = fm.temporaryDirectory.appendingPathComponent("plume-fixtures-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: draft) }
        try FixtureSamples.write(to: draft)
        try fm.moveItem(at: draft, to: folder)
    }
}
