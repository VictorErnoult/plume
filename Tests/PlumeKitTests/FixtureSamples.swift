import Foundation
@testable import PlumeKit

/// Les données inventées des échantillons de `Tests/Fixtures/` : le générateur les écrit, les
/// tests vérifient que les fichiers n'en contiennent pas d'autres. Jamais de vraie donnée ici.
/// On ajoute, on ne modifie pas : les échantillons déjà générés en dépendent.
enum FixtureSamples {
    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Une dictée où tout est renseigné.
    static let dictation = Transcript(
        id: "2026-10-02_09-15-00", createdAt: date("2026-10-02T07:15:00Z"), mode: .dictation, device: "mac",
        duration: 4.2, engine: "parakeet-ultra", text: "Le rapport trimestriel est prêt, je te l'envoie ce soir.",
        rawText: "euh le rapport trimestriel est prêt je te l'envoie ce soir",
        audioFiles: ["2026-10-02_09-15-00_mic.m4a"], app: "Notes", title: "Rapport trimestriel",
        summary: "Rapport prêt, envoi ce soir.")

    /// Une réunion : les deux canaux, des interlocuteurs, un titre et un résumé.
    static let meeting = Transcript(
        id: "2026-10-02_14-31-05", createdAt: date("2026-10-02T12:31:05Z"), mode: .meeting, device: "mac",
        duration: 1834.5, engine: "parakeet-ultra",
        text: "**Moi** : On commence par le budget.\n\n**Inès** : D'accord, je partage l'écran.",
        rawText: "on commence par le budget d'accord je partage l'écran",
        segments: [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 3.25, text: "On commence par le budget."),
            Segment(id: 1, speaker: "Inès", channel: .system, start: 3.5, end: 6, text: "D'accord, je partage l'écran."),
        ],
        speakers: ["Moi", "Inès"], audioFiles: ["2026-10-02_14-31-05_mic.m4a", "2026-10-02_14-31-05_sys.m4a"],
        app: "Zoom", title: "Point budget", summary: "## Points clés\n- Budget validé.")

    /// Un import réduit aux champs obligatoires, comme un fichier d'avant `app`, `title` et `summary`.
    static let imported = Transcript(
        id: "2026-10-03_08-00-00", createdAt: date("2026-10-03T06:00:00Z"), mode: .imported, device: "mac",
        duration: 62, engine: "parakeet-v3", text: "Message vocal : rappelle-moi demain.",
        rawText: "message vocal rappelle-moi demain")

    static let transcripts = [dictation, meeting, imported]

    static let cancelled = CancelledRecording(
        id: "2026-10-03_10-00-00", createdAt: date("2026-10-03T08:00:00Z"), cancelledAt: date("2026-10-03T08:01:30Z"),
        mode: .dictation, duration: 12.5, app: "Mail", text: "Petite précision sur l'ordre du jour.",
        rawText: "petite précision sur l'ordre du jour", audioFiles: ["2026-10-03_10-00-00_mic.m4a"])

    static let replacements = [
        Replacement(id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000001")!, original: "sitié", with: "CTA"),
        Replacement(id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000002")!, original: "ma signature", with: "Paul\nÉquipe Plume"),
    ]

    /// Une règle par style, dont celle de toutes les autres applications.
    static let rules = [
        AppRule(
            id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000003")!, bundleID: "com.apple.mail", name: "Mail",
            style: .standard, polish: true, instructions: "Ton cordial."),
        AppRule(
            id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000004")!, bundleID: "com.tinyspeck.slackmacgap", name: "Slack",
            style: .message, pressReturn: true),
        AppRule(
            id: UUID(uuidString: "6F1C2A10-0000-4000-8000-000000000005")!, bundleID: "*", name: "Toutes les autres",
            style: .casual, typeText: true),
    ]

    static let voiceprint = Voiceprint(embedding: [0.125, -0.5, 0.25, 0.75], samples: 3)

    /// Une sauvegarde avec toutes les clés que la 1.0.1 savait sauvegarder (`SettingsBackup.*Keys`).
    static let backup = SettingsBackup.File(
        date: date("2026-10-03T09:00:00Z"),
        shortcuts: [
            PlumeSettings.Key.dictationShortcut: Shortcut(keyCode: 49, modifiers: ModifierMask.option),
            PlumeSettings.Key.meetingShortcut: Shortcut(keyCode: nil, modifiers: ModifierMask.control | ModifierMask.shift),
            PlumeSettings.Key.openShortcut: Shortcut(keyCode: 35, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.pasteLastShortcut: Shortcut(keyCode: 9, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.transformShortcut: Shortcut(keyCode: 17, modifiers: ModifierMask.control | ModifierMask.option),
            PlumeSettings.Key.cancelShortcut: Shortcut(keyCode: 53, modifiers: 0),
            PlumeSettings.Key.restoreShortcut: Shortcut(keyCode: 15, modifiers: ModifierMask.control | ModifierMask.option),
        ],
        booleans: Dictionary(uniqueKeysWithValues: SettingsBackup.booleanKeys.map { ($0, $0 != PlumeSettings.Key.keepHistory) }),
        numbers: [
            PlumeSettings.Key.soundVolume: 0.5, PlumeSettings.Key.audioRetentionDays: 30,
            PlumeSettings.Key.cancelledRetentionHours: 48,
        ],
        strings: [
            PlumeSettings.Key.model: "parakeet-ultra", PlumeSettings.Key.soundPack: "pluck",
            PlumeSettings.Key.appearance: "dark", PlumeSettings.Key.polishInstructions: "Phrases courtes.",
            PlumeSettings.Key.language: "fr",
        ],
        replacements: replacements, rules: rules)

    /// Écrit les échantillons dans `folder` avec le code de l'app, par des chemins explicites
    /// seulement (jamais les réglages, le dossier de support ni le dossier personnel), et ne
    /// garde que les fichiers JSON que l'app relit : Markdown, index, audio et mode d'emploi se
    /// régénèrent.
    static func write(to folder: URL) throws {
        // La sauvegarde des réglages, comme `export`, écrit dans un dossier qui existe.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = folder.appendingPathComponent("library", isDirectory: true)
        let store = TranscriptStore(root: library)
        for transcript in transcripts { try store.save(transcript) }
        try CancelledStore(library: library).keep(cancelled, mic: [Float](repeating: 0, count: 16_000))

        let support = folder.appendingPathComponent("support", isDirectory: true)
        try ReplacementStore.write(replacements, to: support.appendingPathComponent("remplacements.json"))
        try AppRuleStore.write(rules, to: support.appendingPathComponent("applications.json"))
        try VoiceprintStore.write(voiceprint, to: support.appendingPathComponent("empreinte-vocale.json"))
        try SettingsBackup.write(backup, to: folder.appendingPathComponent("reglages.json"))

        let fm = FileManager.default
        let everything = (fm.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        for url in everything where !url.hasDirectoryPath && url.pathExtension != "json" {
            try fm.removeItem(at: url)
        }
    }

    /// Toutes les valeurs que les échantillons contiennent, telles que l'app les encode (textes,
    /// dates, identifiants, nombres, empreinte vocale comprise), chacune en texte JSON.
    static var allLeaves: Set<String> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var leaves = Set<String>()
        func add<T: Encodable>(_ value: T) {
            guard let data = try? encoder.encode(value),
                let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { return }
            leaves.formUnion(Fixtures.leaves(in: object))
        }
        add(transcripts)
        add(cancelled)
        add(replacements)
        add(rules)
        add(voiceprint)
        add(backup)
        return leaves
    }
}

/// `Tests/Fixtures/` : un dossier par version qui a changé un format, avec les fichiers JSON que
/// cette version écrivait et que l'app doit toujours savoir relire.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    /// Un nom de dossier de version : `1.0.1`, `1.10`.
    static func isVersion(_ name: String) -> Bool {
        name.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
    }

    /// Les dossiers de version, du plus ancien au plus récent (ordre numérique : 1.9 avant
    /// 1.10). Tout autre fichier ou dossier est ignoré.
    static var versions: [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return isVersion(name)
                && fm.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        .map { root.appendingPathComponent($0, isDirectory: true) }
    }

    /// Tous les fichiers JSON d'un dossier, dossiers cachés compris (`.annules`).
    static func jsonFiles(in folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL]) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    static func object(at url: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
    }

    /// Les valeurs d'un document JSON (pas les noms des clés), chacune en texte JSON : `"Inès"`,
    /// `0.5`, `true`. Le texte distingue `true` de `1`, que `NSNumber` confond.
    static func leaves(in value: Any) -> Set<String> {
        switch value {
        case let array as [Any]:
            return array.reduce(into: Set<String>()) { $0.formUnion(leaves(in: $1)) }
        case let object as [String: Any]:
            return object.values.reduce(into: Set<String>()) { $0.formUnion(leaves(in: $1)) }
        default:
            return [json(value)]
        }
    }

    /// Les valeurs d'un document JSON avec leur chemin (`.segments[1].text`), comme `missing`.
    static func leaves(in value: Any, at path: String) -> [(path: String, value: String)] {
        switch value {
        case let array as [Any]:
            return array.enumerated().flatMap { index, element in leaves(in: element, at: "\(path)[\(index)]") }
        case let object as [String: Any]:
            return object.keys.sorted().flatMap { key in leaves(in: object[key]!, at: path + "." + key) }
        default:
            return [(path, json(value))]
        }
    }

    /// Une valeur simple en texte JSON.
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
    }

    /// Ce que `original` contient et que `copy` n'a plus, ou plus à l'identique : les chemins
    /// (`.segments[1].speaker`). Vide quand rien ne se perd.
    static func missing(_ original: Any, in copy: Any, at path: String = "") -> [String] {
        switch (original, copy) {
        case let (original as [String: Any], copy as [String: Any]):
            return original.keys.sorted().flatMap { key in
                copy[key].map { missing(original[key]!, in: $0, at: path + "." + key) } ?? [path + "." + key]
            }
        case let (original as [Any], copy as [Any]):
            guard original.count == copy.count else { return [path] }
            return zip(original, copy).enumerated().flatMap { index, pair in
                missing(pair.0, in: pair.1, at: "\(path)[\(index)]")
            }
        default:
            return json(original) == json(copy) ? [] : [path]
        }
    }
}
