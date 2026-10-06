import Foundation
import Testing
@testable import PlumeKit

/// Écrit `Tests/Fixtures/<version>/` à partir de `FixtureSamples`, avec le code de l'app :
/// `FIXTURES_VERSION=1.0.1 ./scripts/test.sh --filter FixtureGenerator`. Le dossier d'une
/// version pas encore publiée (sans tag `v<version>`) se supprime à la main puis se régénère.
@Suite("Générateur d'échantillons")
struct FixtureGenerator {
    static let version = ProcessInfo.processInfo.environment["FIXTURES_VERSION"]

    @Test(.enabled(if: version != nil, "FIXTURES_VERSION=<version> pour écrire un dossier d'échantillons"))
    func écritLesÉchantillonsDeCetteVersion() throws {
        let version = try #require(Self.version)
        try #require(Fixtures.isVersion(version), "FIXTURES_VERSION doit être un numéro de version (1.0.2), pas « \(version) »")
        let folder = Fixtures.root.appendingPathComponent(version, isDirectory: true)
        let fm = FileManager.default
        try #require(!fm.fileExists(atPath: folder.path), "Tests/Fixtures/\(version) existe déjà : on n'y touche pas")
        // Écrit à part, puis mis en place d'un coup : une erreur ne laisse pas de dossier à moitié écrit.
        let draft = fm.temporaryDirectory.appendingPathComponent("plume-fixtures-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: draft) }
        try FixtureSamples.write(to: draft)
        try fm.moveItem(at: draft, to: folder)
    }
}
