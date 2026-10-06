import Foundation
import Testing
@testable import PlumeKit

/// Les fichiers de réglages annexes se lisent et s'écrivent à un endroit donné : les tests et le
/// générateur d'échantillons passent par le même code que l'app, sans toucher au vrai dossier.
@Suite("Fichiers de réglages")
struct StoreFileTests {
    private func temporaryFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    @Test func leVocabulaireSeRelitTelQuel() throws {
        let url = temporaryFile("remplacements.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let items = [Replacement(original: "sitié", with: "CTA"), Replacement(original: "ma signature", with: "Paul\nÉquipe")]
        try ReplacementStore.write(items, to: url)
        #expect(ReplacementStore.read(from: url) == items)
    }

    @Test func lesRèglesSeRelisentTellesQuelles() throws {
        let url = temporaryFile("applications.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let rules = [AppRule(bundleID: "com.apple.mail", name: "Mail", style: .message, pressReturn: true)]
        try AppRuleStore.write(rules, to: url)
        #expect(AppRuleStore.read(from: url) == rules)
    }

    @Test func lEmpreinteVocaleSeRelitTelleQuelle() throws {
        let url = temporaryFile("empreinte-vocale.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try VoiceprintStore.write(Voiceprint(embedding: [0.125, -0.5], samples: 2), to: url)
        let read = try #require(VoiceprintStore.read(from: url))
        #expect(read.embedding == [0.125, -0.5])
        #expect(read.samples == 2)
    }

    @Test func laSauvegardeDesRéglagesSeRelitTelleQuelle() throws {
        let url = temporaryFile("reglages.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Comme `export`, `write` écrit dans un dossier qui existe.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = SettingsBackup.File(
            date: Date(timeIntervalSince1970: 1_790_000_000),
            shortcuts: [PlumeSettings.Key.dictationShortcut: Shortcut(keyCode: 49, modifiers: ModifierMask.option)],
            booleans: [PlumeSettings.Key.cleanup: false], numbers: [PlumeSettings.Key.soundVolume: 0.5],
            strings: [PlumeSettings.Key.language: "fr"], replacements: [], rules: [])
        try SettingsBackup.write(file, to: url)
        #expect(try SettingsBackup.read(from: url) == file)
    }

    @Test func unFichierAbsentOuIllisibleNeSeLitPas() throws {
        let url = temporaryFile("remplacements.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(ReplacementStore.read(from: url) == nil)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: url)
        #expect(ReplacementStore.read(from: url) == nil)
        #expect(AppRuleStore.read(from: url) == nil)
        #expect(VoiceprintStore.read(from: url) == nil)
        #expect(throws: (any Error).self) { try SettingsBackup.read(from: url) }
    }
}
