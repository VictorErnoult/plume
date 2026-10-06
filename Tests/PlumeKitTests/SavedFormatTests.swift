import Foundation
import Testing
@testable import PlumeKit

/// Les fichiers écrits par une version publiée (`Tests/Fixtures/<version>/`) : l'app doit
/// toujours les relire, et les réécrire sans rien perdre.
@Suite("Fichiers des versions publiées")
struct SavedFormatTests {
    /// Champs ou réglages retirés exprès, chacun avec sa ligne dans `CHANGELOG.md` : les
    /// échantillons qui les contiennent encore n'en sont pas retouchés, ce n'est pas une perte.
    /// Chaque entrée est un chemin exact, sans indices, valable dans tous les fichiers : un champ
    /// (`.summary`, `.segments.speaker`), un réglage par sa table (`.booleans.polish`). Un champ
    /// présent à plusieurs endroits s'y inscrit pour chacun (`.polish` dans `applications.json`,
    /// `.rules.polish` dans la sauvegarde). Une entrée exempte aussi son chemin de la vérification
    /// des données inventées : ses valeurs ont été vérifiées quand le dossier a été produit.
    /// Une entrée couvre aussi ce qui se trouve sous elle : `.shortcuts.transformShortcut` couvre
    /// son `keyCode`.
    static let removedOnPurpose: Set<String> = []

    /// Une perte excusée : le chemin, sans ses indices, est une entrée de la liste ou se trouve
    /// dessous (un raccourci retiré couvre son `keyCode` et ses `modifiers`).
    static func isExcused(_ path: String, by entries: Set<String> = removedOnPurpose) -> Bool {
        let bare = path.replacingOccurrences(of: #"\[[0-9]+\]"#, with: "", options: .regularExpression)
        return entries.contains { bare == $0 || bare.hasPrefix($0 + ".") }
    }

    @Test func ilYAAuMoinsUneVersion() {
        #expect(!Fixtures.versions.isEmpty, "Tests/Fixtures/ est vide")
    }

    /// Le dépôt est public : un échantillon ne contient que des données inventées (textes et
    /// nombres : l'empreinte vocale n'a que des nombres), et que des fichiers JSON.
    @Test func lesÉchantillonsNeContiennentQueDesDonnéesInventées() throws {
        let fm = FileManager.default
        // À la racine, rien que des dossiers de version : un fichier ou un lien y échapperait
        // aux vérifications ci-dessous.
        let rootKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = (try? fm.contentsOfDirectory(at: Fixtures.root, includingPropertiesForKeys: Array(rootKeys))) ?? []
        let stray = entries.filter { url in
            let values = try? url.resourceValues(forKeys: rootKeys)
            let isVersionFolder = values?.isDirectory == true && values?.isSymbolicLink != true
                && Fixtures.isVersion(url.lastPathComponent)
            return !isVersionFolder && url.lastPathComponent != ".DS_Store"
        }
        #expect(stray.isEmpty, "Tests/Fixtures : seuls des dossiers de version \(stray.map(\.lastPathComponent).sorted())")
        let invented = FixtureSamples.allLeaves
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        for version in Fixtures.versions {
            let everything = (fm.enumerator(at: version, includingPropertiesForKeys: keys)?.allObjects as? [URL]) ?? []
            // Un lien symbolique compte comme un fichier : git garderait son chemin cible.
            let others = everything.filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory != true, url.lastPathComponent != ".DS_Store" else { return false }
                return url.pathExtension != "json" || values?.isSymbolicLink == true
            }
            #expect(others.isEmpty, "\(version.lastPathComponent) : pas du JSON \(others.map(\.lastPathComponent))")
            for file in Fixtures.jsonFiles(in: version) {
                // Ce qui a été retiré exprès n'est plus dans les échantillons d'aujourd'hui.
                let kept = Fixtures.leaves(in: try Fixtures.object(at: file), at: "").filter { !Self.isExcused($0.path) }
                let unknown = Set(kept.map(\.value)).subtracting(invented)
                #expect(unknown.isEmpty, "\(file.path) : \(unknown.sorted())")
            }
        }
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Relu puis réécrit par l'app, un fichier garde chaque clé et chaque valeur d'origine,
    /// hormis ce qui a été retiré exprès.
    private func expectNothingLost(_ original: Any, rewritten: URL, _ name: String) throws {
        let lost = Fixtures.missing(original, in: try Fixtures.object(at: rewritten)).filter { path in
            !Self.isExcused(path)
        }
        #expect(lost.isEmpty, "\(name) perd \(lost)")
    }

    @Test func lesTranscriptionsSeRelisentEtSeRéécriventSansPerte() throws {
        for version in Fixtures.versions {
            let library = temporaryFolder()
            try FileManager.default.copyItem(at: version.appendingPathComponent("library"), to: library)
            defer { try? FileManager.default.removeItem(at: library) }
            let files = Fixtures.jsonFiles(in: library).filter { !$0.path.contains("/.annules/") }
            let store = TranscriptStore(root: library)
            let listed = store.list()
            #expect(listed.count == files.count, "\(version.lastPathComponent) : \(listed.count) relues sur \(files.count)")
            if listed.count != files.count {
                // Une transcription qui ne se relit plus : dire pourquoi (souvent un champ
                // obligatoire ajouté, voir AGENTS.md) plutôt que laisser chercher.
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                for file in files {
                    do { _ = try decoder.decode(Transcript.self, from: Data(contentsOf: file)) } catch {
                        Issue.record("\(version.lastPathComponent)/\(file.lastPathComponent) : \(error)")
                    }
                }
            }
            #expect(listed.map(\.id) == listed.map(\.id).sorted(by: >))
            #expect(store.latest()?.id == listed.first?.id)
            for transcript in listed {
                let file = try #require(files.first { $0.lastPathComponent.hasPrefix(transcript.id + "_") })
                let original = try Fixtures.object(at: file)
                #expect(store.load(id: transcript.id) == transcript)
                // Vidé d'abord : si l'app réécrivait ailleurs, la comparaison le verrait.
                try Data("{}".utf8).write(to: file)
                try store.save(transcript)
                try expectNothingLost(original, rewritten: file, "\(version.lastPathComponent)/\(file.lastPathComponent)")
            }
        }
    }

    @Test func lesAnnulésSeRelisentEtSeRéécriventSansPerte() throws {
        for version in Fixtures.versions {
            let library = temporaryFolder()
            try FileManager.default.copyItem(at: version.appendingPathComponent("library"), to: library)
            defer { try? FileManager.default.removeItem(at: library) }
            let files = Fixtures.jsonFiles(in: library.appendingPathComponent(".annules"))
            let cancelled = CancelledStore(library: library)
            let listed = cancelled.list()
            #expect(listed.count == files.count, "\(version.lastPathComponent) : \(listed.count) relus sur \(files.count)")
            for recording in listed {
                let file = try #require(files.first { $0.lastPathComponent == recording.id + ".json" })
                let original = try Fixtures.object(at: file)
                // Vidé d'abord : si l'app réécrivait ailleurs, la comparaison le verrait.
                try Data("{}".utf8).write(to: file)
                cancelled.update(recording)
                try expectNothingLost(original, rewritten: file, "\(version.lastPathComponent)/\(file.lastPathComponent)")
            }
        }
    }

    @Test func lesRéglagesAnnexesSeRelisentEtSeRéécriventSansPerte() throws {
        let output = temporaryFolder()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        for version in Fixtures.versions {
            let name = version.lastPathComponent
            let support = version.appendingPathComponent("support")

            let vocabulary = support.appendingPathComponent("remplacements.json")
            let replacements = try #require(ReplacementStore.read(from: vocabulary), "\(name) : vocabulaire illisible")
            try ReplacementStore.write(replacements, to: output.appendingPathComponent("\(name)-remplacements.json"))
            try expectNothingLost(try Fixtures.object(at: vocabulary), rewritten: output.appendingPathComponent("\(name)-remplacements.json"), "\(name)/remplacements.json")

            let applications = support.appendingPathComponent("applications.json")
            let rules = try #require(AppRuleStore.read(from: applications), "\(name) : règles illisibles")
            try AppRuleStore.write(rules, to: output.appendingPathComponent("\(name)-applications.json"))
            try expectNothingLost(try Fixtures.object(at: applications), rewritten: output.appendingPathComponent("\(name)-applications.json"), "\(name)/applications.json")

            let print = support.appendingPathComponent("empreinte-vocale.json")
            let voiceprint = try #require(VoiceprintStore.read(from: print), "\(name) : empreinte illisible")
            try VoiceprintStore.write(voiceprint, to: output.appendingPathComponent("\(name)-empreinte.json"))
            try expectNothingLost(try Fixtures.object(at: print), rewritten: output.appendingPathComponent("\(name)-empreinte.json"), "\(name)/empreinte-vocale.json")

            let backupURL = version.appendingPathComponent("reglages.json")
            let backup = try SettingsBackup.read(from: backupURL)
            try SettingsBackup.write(backup, to: output.appendingPathComponent("\(name)-reglages.json"))
            try expectNothingLost(try Fixtures.object(at: backupURL), rewritten: output.appendingPathComponent("\(name)-reglages.json"), "\(name)/reglages.json")
        }
    }

    /// Une clé de réglage renommée remettrait ce réglage à sa valeur par défaut chez tout le
    /// monde (`keepHistory`, l'interrupteur de confidentialité, vaut `true` par défaut).
    @Test func chaqueRéglageSauvegardéEstToujoursReconnu() throws {
        for version in Fixtures.versions {
            let backup = try SettingsBackup.read(from: version.appendingPathComponent("reglages.json"))
            let name = version.lastPathComponent
            let unknown = Set(backup.booleans.keys.filter { !SettingsBackup.booleanKeys.contains($0) }.map { ".booleans.\($0)" })
                .union(backup.numbers.keys.filter { !SettingsBackup.numberKeys.contains($0) }.map { ".numbers.\($0)" })
                .union(backup.strings.keys.filter { !SettingsBackup.stringKeys.contains($0) }.map { ".strings.\($0)" })
                .union(backup.shortcuts.keys.filter { !SettingsBackup.shortcutKeys.contains($0) }.map { ".shortcuts.\($0)" })
                .subtracting(Self.removedOnPurpose)
            #expect(unknown.isEmpty, "\(name) : réglages plus reconnus \(unknown.sorted())")
        }
    }

    /// Ces réglages ne sont pas dans la sauvegarde, mais chaque Mac les a rangés sous ce nom :
    /// `libraryPath` renommé, et une bibliothèque déplacée semblerait vide.
    @Test func lesRéglagesHorsSauvegardeGardentLeurNom() {
        #expect(PlumeSettings.Key.libraryPath == "libraryPath")
        #expect(PlumeSettings.Key.microphoneUID == "microphoneUID")
        #expect(PlumeSettings.Key.customModelPath == "customModelPath")
        #expect(PlumeSettings.Key.onboarded == "onboarded")
        #expect(PlumeSettings.Key.changelogSeen == "changelogSeen")
    }

    /// Un format qui change ajoute le dossier de sa version : le plus récent contient tout ce que
    /// le code d'aujourd'hui écrit pour les mêmes échantillons.
    @Test func leDernierDossierEstÀJour() throws {
        let newest = try #require(Fixtures.versions.last)
        let today = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: today) }
        try FixtureSamples.write(to: today)
        let command = "FIXTURES_VERSION=<version> ./scripts/test.sh --filter FixtureGenerator"
        let base = today.resolvingSymlinksInPath().path + "/"
        for file in Fixtures.jsonFiles(in: today) {
            let relative = String(file.resolvingSymlinksInPath().path.dropFirst(base.count))
            let frozen = newest.appendingPathComponent(relative)
            let name = "\(newest.lastPathComponent)/\(relative)"
            guard FileManager.default.fileExists(atPath: frozen.path) else {
                Issue.record("\(name) manque : \(command)")
                continue
            }
            let lost = Fixtures.missing(try Fixtures.object(at: file), in: try Fixtures.object(at: frozen))
            #expect(lost.isEmpty, "\(name) n'a pas \(lost) : \(command)")
        }
    }

    /// Les échantillons complets renseignent chaque champ facultatif : un champ ajouté sans
    /// valeur d'exemple n'apparaîtrait dans aucun échantillon.
    @Test func lesÉchantillonsCompletsRenseignentChaqueChamp() {
        func unset(_ value: Any) -> [String] {
            Mirror(reflecting: value).children.compactMap { child in
                let mirror = Mirror(reflecting: child.value)
                return mirror.displayStyle == .optional && mirror.children.isEmpty ? child.label : nil
            }
        }
        #expect(unset(FixtureSamples.dictation).isEmpty, "dictée : \(unset(FixtureSamples.dictation))")
        #expect(unset(FixtureSamples.meeting).isEmpty, "réunion : \(unset(FixtureSamples.meeting))")
        #expect(unset(FixtureSamples.cancelled).isEmpty, "annulé : \(unset(FixtureSamples.cancelled))")
    }

    /// Les échantillons couvrent chaque valeur que ces fichiers peuvent contenir : un cas ajouté à
    /// une énumération, ou un réglage ajouté à la sauvegarde, doit y entrer aussi.
    @Test func lesÉchantillonsCouvrentToutesLesValeurs() {
        #expect(Set(FixtureSamples.transcripts.map(\.mode)) == Set(RecordingMode.allCases))
        #expect(Set(FixtureSamples.rules.map(\.style)) == Set(DictationStyle.allCases))
        #expect(Set(FixtureSamples.meeting.segments.map(\.channel)) == Set(AudioChannel.allCases))
        #expect(Set(FixtureSamples.backup.booleans.keys) == Set(SettingsBackup.booleanKeys))
        #expect(Set(FixtureSamples.backup.numbers.keys) == Set(SettingsBackup.numberKeys))
        #expect(Set(FixtureSamples.backup.strings.keys) == Set(SettingsBackup.stringKeys))
        #expect(Set(FixtureSamples.backup.shortcuts.keys) == Set(SettingsBackup.shortcutKeys))
    }

    /// `NSNumber` confond `true` et `1` : un booléen devenu nombre passerait la relecture sans perte.
    @Test func lesValeursSeComparentTellesQuelles() {
        #expect(!Fixtures.missing(["a": true], in: ["a": 1]).isEmpty)
        #expect(!Fixtures.missing(["a": [1, 2]], in: ["a": [1]]).isEmpty)
        #expect(Fixtures.missing(["a": 6, "b": ["c": "d"]], in: ["a": 6, "b": ["c": "d", "e": 1], "f": 2]).isEmpty)
    }

    /// Une entrée n'excuse que le chemin qu'elle nomme : ni le réglage du même nom, ni l'inverse.
    @Test func uneEntréeRetiréeNExcuseQueCeQuElleNomme() {
        #expect(Self.isExcused("[0].polish", by: [".polish"]))
        #expect(Self.isExcused(".rules[2].polish", by: [".rules.polish"]))
        #expect(!Self.isExcused(".rules[2].polish", by: [".polish"]))
        #expect(!Self.isExcused(".rules[2].polish", by: [".booleans.polish"]))
        #expect(!Self.isExcused(".booleans.polish", by: [".polish"]))
        #expect(!Self.isExcused(".booleans.polish", by: [".rules.polish"]))
        #expect(!Self.isExcused(".booleans.autopolish", by: ["polish"]))
        #expect(!Self.isExcused(".summary", by: [".booleans.polish"]))
        #expect(Self.isExcused(".shortcuts.transformShortcut.keyCode", by: [".shortcuts.transformShortcut"]))
        #expect(!Self.isExcused(".shortcuts.transformShortcutX.keyCode", by: [".shortcuts.transformShortcut"]))
    }
}
