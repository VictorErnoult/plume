import Foundation

/// On-disk transcript library: a folder readable by a human as well as by an AI.
///
///     ~/Plume/
///       README.md                    how to use the folder (for AIs)
///       latest.md                    the most recent transcript
///       dernier.md                   deprecated plain copy of latest.md, for older scripts
///       index.jsonl                  one JSON line per transcript, oldest to newest
///       2026-10/
///         2026-10-02_14-31-05_dictee.md      readable text, with header
///         2026-10-02_14-31-05_dictee.json    full data (segments, speakers)
///         2026-10-02_14-31-05_mic.m4a        audio
public final class TranscriptStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    /// Lock shared by all instances: several may target the same folder.
    private static let sharedLock = NSRecursiveLock()
    private var lock: NSRecursiveLock { Self.sharedLock }
    /// Identifiers already assigned in this process, including those whose file is not written yet.
    private static var issued = Set<String>()

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Identifiers and paths

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    /// "Oct 2, 2026 at 11:30 AM" or "2 oct. 2026 à 11:30", depending on the language in force.
    private static var titleFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.current.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    /// Free identifier for this date. On a collision within the same second, a letter
    /// (`b`, `c`…) is added: alphabetical order of the files stays chronological order.
    public func makeID(for date: Date = Date()) -> String {
        lock.lock()
        defer { lock.unlock() }
        let base = Self.idFormatter.string(from: date)
        var candidate = base
        var letter = UInt8(ascii: "b")
        // Reserved right away: two imports started in the same second don't step on each other.
        while Self.issued.contains(root.path + "/" + candidate) || existingJSON(forID: candidate) != nil,
            letter <= UInt8(ascii: "z")
        {
            candidate = base + String(UnicodeScalar(letter))
            letter += 1
        }
        Self.issued.insert(root.path + "/" + candidate)
        return candidate
    }

    /// Date carried by an identifier (`2026-10-02_14-31-05`, possibly followed by a letter).
    public static func date(fromID id: String) -> Date? {
        idFormatter.date(from: String(id.prefix(19)))
    }

    /// Monthly folder of an identifier (`2026-10`).
    public func directory(forID id: String) -> URL {
        root.appendingPathComponent(String(id.prefix(7)), isDirectory: true)
    }

    public func ensureDirectory(forID id: String) throws -> URL {
        let dir = directory(forID: id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func existingJSON(forID id: String) -> URL? {
        let dir = directory(forID: id)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        guard let name = names.first(where: { $0.hasPrefix(id + "_") && $0.hasSuffix(".json") }) else { return nil }
        return dir.appendingPathComponent(name)
    }

    public func markdownURL(for t: Transcript) -> URL {
        directory(forID: t.id).appendingPathComponent("\(t.id)_\(t.mode.slug).md")
    }

    public func jsonURL(for t: Transcript) -> URL {
        directory(forID: t.id).appendingPathComponent("\(t.id)_\(t.mode.slug).json")
    }

    public func audioURLs(for t: Transcript) -> [URL] {
        let dir = directory(forID: t.id)
        return t.audioFiles.map { dir.appendingPathComponent($0) }
    }

    // MARK: - Writing

    public func save(_ t: Transcript) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureRoot()
        _ = try ensureDirectory(forID: t.id)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(t).write(to: jsonURL(for: t), options: .atomic)

        let md = Self.markdown(for: t)
        try md.write(to: markdownURL(for: t), atomically: true, encoding: .utf8)

        if latestUnlocked()?.id == t.id { refreshLatest() }
        try? rebuildIndexUnlocked()
    }

    /// Renames a speaker throughout the transcript ("Speaker 1" → "Victor").
    @discardableResult
    public func renameSpeaker(id: String, from old: String, to new: String) throws -> Transcript? {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old, var t = load(id: id) else { return nil }
        for index in t.segments.indices where t.segments[index].speaker == old {
            t.segments[index].speaker = name
        }
        t.speakers = TranscriptBuilder.speakers(in: t.segments)
        t.text = TranscriptBuilder.text(for: t.segments)
        try save(t)
        return t
    }

    public func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let t = loadUnlocked(id: id) else { return }
        var urls = [jsonURL(for: t), markdownURL(for: t)]
        urls.append(contentsOf: audioURLs(for: t))
        for url in urls where fm.fileExists(atPath: url.path) {
            try fm.trashItem(at: url, resultingItemURL: nil)
        }
        refreshLatest()
        try? rebuildIndexUnlocked()
    }

    /// Creates the library folder and its usage guide, if they don't exist yet.
    public func prepare() {
        lock.lock()
        defer { lock.unlock() }
        try? ensureRoot()
    }

    private func ensureRoot() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let readme = root.appendingPathComponent("README.md")
        if !fm.fileExists(atPath: readme.path) {
            try Self.readme.write(to: readme, atomically: true, encoding: .utf8)
        }
        retireLegacyGuide()
        // Right after an upgrade `latest.md` doesn't exist yet, and an older version sharing the
        // folder only updates `dernier.md`: don't wait for the next save. One read and a compare.
        let current = try? String(contentsOf: root.appendingPathComponent("latest.md"), encoding: .utf8)
        if current == nil || current != latestUnlocked().map(Self.markdown(for:)) { refreshLatest() }
    }

    /// Removes the French `LISEZMOI.md` only if it is exactly what an earlier version wrote and
    /// `README.md` is Plume's own: an edited guide, or a README the user wrote, stays untouched.
    private func retireLegacyGuide() {
        let old = root.appendingPathComponent("LISEZMOI.md")
        let new = root.appendingPathComponent("README.md")
        guard let oldText = try? String(contentsOf: old, encoding: .utf8), oldText == Self.legacyReadme,
            let newText = try? String(contentsOf: new, encoding: .utf8), newText == Self.readme
        else { return }
        try? fm.removeItem(at: old)
    }

    /// Writes the newest transcript to `latest.md`, and to `dernier.md` as a plain copy (no
    /// symlink: synced folders and some readers mishandle links). With no transcript, removes
    /// only files that are Plume's own (front matter): the folder may be the user's.
    /// Call with the lock held.
    private func refreshLatest() {
        let names = ["latest.md", "dernier.md"].map { root.appendingPathComponent($0) }
        guard let latest = latestUnlocked() else {
            for url in names where (try? String(contentsOf: url, encoding: .utf8))?.hasPrefix("---\nid: ") == true {
                try? fm.removeItem(at: url)
            }
            return
        }
        let md = Self.markdown(for: latest)
        for url in names { try? md.write(to: url, atomically: true, encoding: .utf8) }
    }

    // MARK: - Reading

    /// All transcript JSON files, from newest to oldest.
    private func allJSONFiles() -> [URL] {
        guard let months = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var files: [URL] = []
        for month in months where month.count == 7 && month.dropFirst(4).first == "-" {
            let dir = root.appendingPathComponent(month, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".json") {
                files.append(dir.appendingPathComponent(name))
            }
        }
        return files.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func decode(_ url: URL) -> Transcript? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Transcript.self, from: data)
    }

    private func loadUnlocked(id: String) -> Transcript? {
        existingJSON(forID: id).flatMap(decode)
    }

    private func latestUnlocked() -> Transcript? {
        allJSONFiles().lazy.compactMap(self.decode).first
    }

    public func load(id: String) -> Transcript? {
        loadUnlocked(id: id)
    }

    public func list(limit: Int? = nil, mode: RecordingMode? = nil) -> [Transcript] {
        var out: [Transcript] = []
        for url in allJSONFiles() {
            if let mode, !url.lastPathComponent.hasSuffix("_\(mode.slug).json") { continue }
            guard let t = decode(url) else { continue }
            out.append(t)
            if let limit, out.count >= limit { break }
        }
        return out
    }

    public func latest(mode: RecordingMode? = nil) -> Transcript? {
        list(limit: 1, mode: mode).first
    }

    /// Full-text search, case- and accent-insensitive; all the words must appear.
    public func search(_ query: String, limit: Int = 20) -> [Transcript] {
        let terms = Self.fold(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        var out: [Transcript] = []
        for url in allJSONFiles() {
            guard let t = decode(url) else { continue }
            let haystack = Self.fold(t.text + " " + t.speakers.joined(separator: " "))
            if terms.allSatisfy({ haystack.contains($0) }) {
                out.append(t)
                if out.count >= limit { break }
            }
        }
        return out
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    // MARK: - Index

    private func rebuildIndexUnlocked() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var lines: [String] = []
        for url in allJSONFiles().reversed() {
            guard let t = decode(url) else { continue }
            let entry = IndexEntry(
                id: t.id,
                date: Self.isoFormatter.string(from: t.createdAt),
                mode: t.mode.slug,
                appareil: t.device,
                duree_s: Int(t.duration.rounded()),
                interlocuteurs: t.speakers,
                fichier: "\(String(t.id.prefix(7)))/\(t.id)_\(t.mode.slug).md",
                titre: t.title,
                apercu: t.preview
            )
            if let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        try (lines.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("index.jsonl"), atomically: true, encoding: .utf8)
    }

    private struct IndexEntry: Codable {
        var id: String
        var date: String
        var mode: String
        var appareil: String
        var duree_s: Int
        var interlocuteurs: [String]
        var fichier: String
        var titre: String?
        var apercu: String
    }

    // MARK: - Maintenance

    /// Deletes the audio of transcripts older than `cutoff` (the text stays).
    /// - Returns: the number of transcripts slimmed down.
    @discardableResult
    public func dropAudio(olderThan cutoff: Date) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var count = 0
        for url in allJSONFiles() {
            guard var t = decode(url), !t.audioFiles.isEmpty, t.createdAt < cutoff else { continue }
            for audio in audioURLs(for: t) { try? fm.removeItem(at: audio) }
            t.audioFiles = []
            guard let json = try? jsonEncoder.encode(t) else { continue }
            try? json.write(to: jsonURL(for: t), options: .atomic)
            try? Self.markdown(for: t).write(to: markdownURL(for: t), atomically: true, encoding: .utf8)
            count += 1
        }
        if count > 0 { try? rebuildIndexUnlocked() }
        return count
    }

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Markdown rendering

    /// "Point lancement", or by default "Meeting, Oct 2, 2026 at 11:30 AM" ("Réunion du 2 oct. 2026 à 11:30" in French).
    public static func title(for t: Transcript) -> String {
        if let title = t.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return dateTitle(for: t)
    }

    public static func dateTitle(for t: Transcript) -> String {
        let date = titleFormatter.string(from: t.createdAt)
        return L10n.current == .french ? "\(t.mode.label) du \(date)" : "\(t.mode.label), \(date)"
    }

    public static func markdown(for t: Transcript) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(t.id)")
        lines.append("date: \(isoFormatter.string(from: t.createdAt))")
        lines.append("mode: \(t.mode.slug)")
        lines.append("appareil: \(t.device)")
        lines.append("duree: \(Format.duration(t.duration))")
        if !t.speakers.isEmpty {
            lines.append("interlocuteurs: [\(t.speakers.joined(separator: ", "))]")
        }
        if let app = t.app { lines.append("application: \(app)") }
        lines.append("moteur: \(t.engine)")
        if !t.audioFiles.isEmpty {
            lines.append("audio: [\(t.audioFiles.joined(separator: ", "))]")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(title(for: t))")
        if t.title != nil { lines.append("\(dateTitle(for: t))") }
        lines.append("")
        if let summary = t.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("## " + tr("Summary"))
            lines.append("")
            lines.append(summary)
            lines.append("")
            lines.append("## " + tr("Transcript"))
            lines.append("")
        }
        lines.append(body(for: t))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Transcript body: plain text, or timestamped dialogue if there are several speaker turns.
    public static func body(for t: Transcript) -> String {
        guard t.mode != .dictation, t.speakers.count > 1 else { return t.text }
        return dialogue(t.segments)
    }

    public static func dialogue(_ segments: [Segment]) -> String {
        segments
            .map { "**\($0.speaker)** [\(Format.clock($0.start))] : \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// The guide written to `README.md` for AIs and humans. Every file and key name below is
    /// the real one: `index.jsonl` keys and the mode names stay French because scripts read them.
    static let readme = """
        # Plume — transcript library

        This folder holds every voice transcript Plume produced (dictations, meetings,
        imports). Everything is plain text, meant to be read directly by an AI or a human.

        - `latest.md`: the most recent transcript. `dernier.md` is a deprecated copy of it,
          kept for older scripts; use `latest.md`.
        - `index.jsonl`: one JSON line per transcript, oldest to newest. Keys: `id`,
          `date` (ISO 8601), `mode`, `appareil` (device), `duree_s` (duration in seconds),
          `interlocuteurs` (speakers), `fichier` (path of the `.md` file, relative to this
          folder), `titre` (title, only if set), `apercu` (preview).
        - `YYYY-MM/<id>_<mode>.md`: the text, with a header (date, mode, duration, speakers).
          Modes: `dictee` (dictation), `reunion` (meeting), `import` (imported audio).
        - `YYYY-MM/<id>_<mode>.json`: the full data (segments timestamped per speaker, raw
          text before cleanup).
        - `YYYY-MM/<id>_*.m4a`: the original audio (`mic` = microphone, `sys` = the
          computer's sound).

        For a meeting, each speaker turn is written like this:
        `**Speaker** [mm:ss] : text`. "Me" (written `Moi` in French) is the owner of the device.

        From the command line: `plume last`, `plume list`, `plume search <words>`,
        `plume show <id>`.

        """

    /// The French guide written by 1.0.1 and earlier as `LISEZMOI.md`: recognised, to retire it only if untouched.
    static let legacyReadme = """
        # Plume — bibliothèque de transcriptions

        Ce dossier contient toutes les transcriptions vocales produites par Plume
        (dictées, réunions, imports). Tout est en texte brut, pensé pour être lu
        directement par une IA ou par un humain.

        - `dernier.md` : la transcription la plus récente.
        - `index.jsonl` : une ligne JSON par transcription (id, date, mode, durée,
          interlocuteurs, chemin du fichier, aperçu), de la plus ancienne à la plus récente.
        - `AAAA-MM/<id>_<mode>.md` : le texte, avec un en-tête (date, mode, durée,
          interlocuteurs). Modes : `dictee`, `reunion`, `import`.
        - `AAAA-MM/<id>_<mode>.json` : les données complètes (segments horodatés
          par interlocuteur, texte brut avant nettoyage).
        - `AAAA-MM/<id>_*.m4a` : l'audio d'origine (`mic` = micro, `sys` = son de l'ordinateur).

        Pour une réunion, chaque tour de parole est écrit ainsi :
        `**Interlocuteur** [mm:ss] : texte`. « Moi » désigne le propriétaire de l'appareil.

        En ligne de commande : `plume last`, `plume list`, `plume search <mots>`,
        `plume show <id>`.

        """
}
