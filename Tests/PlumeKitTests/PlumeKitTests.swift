import Foundation
import Testing

@testable import PlumeKit

@Suite("Nettoyage de dictée")
struct TextCleanupTests {
    @Test func retireLesMotsOutilsBégayés() {
        #expect(TextCleanup.clean("et sur mon mon laptop") == "Et sur mon laptop")
        #expect(TextCleanup.clean("c'est c'est toujours le même") == "C'est toujours le même")
        #expect(TextCleanup.clean("sinon pas pas nécessaire") == "Sinon pas nécessaire")
    }

    @Test func retireLesGroupesRépétés() {
        #expect(TextCleanup.clean("ça le ça le ça le marque") == "Ça le marque")
        #expect(TextCleanup.clean("que quand que quand c'est bon") == "Que quand c'est bon")
        #expect(TextCleanup.clean("tout ça c'est tout ça c'est fait") == "Tout ça c'est fait")
    }

    @Test func gardeLesRépétitionsLégitimes() {
        #expect(TextCleanup.clean("Nous nous sommes vus hier.") == "Nous nous sommes vus hier.")
        #expect(TextCleanup.clean("C'est très très bien.") == "C'est très très bien.")
        #expect(TextCleanup.clean("Oui oui, d'accord.") == "Oui oui, d'accord.")
    }

    @Test func neFusionnePasDeuxPhrases() {
        // Une ponctuation entre les deux occurrences signale une vraie reprise.
        #expect(TextCleanup.clean("Je pense à ça. À ça aussi.") == "Je pense à ça. À ça aussi.")
    }

    @Test func retireLesHésitations() {
        #expect(TextCleanup.clean("Alors euh je voulais dire") == "Alors je voulais dire")
        #expect(TextCleanup.clean("Bon, euh. Voilà.") == "Bon, Voilà.")
        #expect(TextCleanup.clean("euh, bonjour") == "Bonjour")
    }
}

@Suite("Remplacements")
struct ReplacementTests {
    let rules = [
        Replacement(original: "super whisper", with: "Superwhisper"),
        Replacement(original: "sitié", with: "CTA"),
    ]

    @Test func insensibleÀLaCasseSurMotsEntiers() {
        #expect(ReplacementStore.apply(rules, to: "J'utilise Super Whisper.") == "J'utilise Superwhisper.")
        #expect(ReplacementStore.apply(rules, to: "Le sitié est rouge") == "Le CTA est rouge")
        #expect(ReplacementStore.apply(rules, to: "la densitié") == "la densitié")
    }

    @Test func ignoreLesRèglesVides() {
        #expect(ReplacementStore.apply([Replacement(original: " ", with: "x")], to: "a b") == "a b")
    }
}

@Suite("Tours de parole")
struct TranscriptBuilderTests {
    func words(_ items: [(String, Double, Double)]) -> [Word] {
        items.map { Word(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test func attribueLesMotsAuxLocuteurs() {
        let w = words([("Bonjour", 0, 0.5), ("Marie.", 0.6, 1.0), ("Salut", 2.0, 2.4), ("Thomas.", 2.5, 3.0)])
        let turns = [SpeakerTurn(speaker: "S1", start: 0, end: 1.2), SpeakerTurn(speaker: "S2", start: 1.8, end: 3.2)]
        let names = TranscriptBuilder.names(for: turns)
        let segments = TranscriptBuilder.segments(words: w, turns: turns, names: names, fallback: "?", channel: .mic)
        #expect(segments.map(\.speaker) == ["Interlocuteur 1", "Interlocuteur 2"])
        #expect(segments.map(\.text) == ["Bonjour Marie.", "Salut Thomas."])
        #expect(segments[1].start == 2.0)
    }

    @Test func rendUnMotIsoléAuLocuteurEnvironnant() {
        let w = words([("je", 0, 0.2), ("pense", 0.3, 0.6), ("que", 0.7, 0.8), ("oui", 0.9, 1.1), ("vraiment", 1.2, 1.6)])
        var labels = ["A", "A", "B", "A", "A"]
        TranscriptBuilder.smooth(&labels, words: w)
        #expect(labels == ["A", "A", "A", "A", "A"])
    }

    @Test func gardeUneRéponseCourteEnFinDePhrase() {
        let w = words([("D'accord", 0, 0.4), ("?", 0.4, 0.5), ("Oui.", 1.0, 1.3), ("Parfait", 2.0, 2.5)])
        var labels = ["A", "A", "B", "A"]
        TranscriptBuilder.smooth(&labels, words: [w[0], Word(text: "d'accord ?", start: 0.4, end: 0.5), w[2], w[3]])
        #expect(labels == ["A", "A", "B", "A"])
    }

    @Test func sansDiarisationToutRevientAuLocuteurParDéfaut() {
        let w = words([("Un", 0, 0.2), ("test.", 0.3, 0.6)])
        let segments = TranscriptBuilder.segments(words: w, turns: [], names: [:], fallback: "Moi", channel: .mic)
        #expect(segments.count == 1)
        #expect(segments[0].speaker == "Moi")
    }

    @Test func ouvreUnParagrapheAprèsUneLonguePause() {
        let w = words([("Premier.", 0, 0.5), ("Second.", 5.0, 5.5)])
        let segments = TranscriptBuilder.segments(words: w, turns: [], names: [:], fallback: "Moi", channel: .mic)
        #expect(segments.count == 2)
    }

    /// Mots système étalés régulièrement à partir de `start`.
    func spread(_ text: String, from start: Double, step: Double = 0.4) -> [Word] {
        text.split(separator: " ").enumerated().map { index, word in
            Word(text: String(word), start: start + Double(index) * step, end: start + Double(index) * step + 0.3)
        }
    }

    @Test func retireLÉchoDuSonSystèmeDansLeMicro() {
        let system = spread("On se retrouve demain à dix heures au bureau.", from: 10)
        let mic = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 10.2, end: 14.1, text: "on se retrouve demain à dix heures au bureau"),
            Segment(id: 1, speaker: "Moi", channel: .mic, start: 15, end: 17, text: "Très bien, je note ça tout de suite."),
        ]
        let kept = TranscriptBuilder.removingEcho(mic: mic, systemWords: system)
        #expect(kept.map(\.id) == [1])
    }

    @Test func gardeUneVraieRéponsePendantUnLongMonologue() {
        // L'autre parle longuement avec des mots courants ; ma réponse les réutilise sans le répéter.
        let monologue = "alors oui je vois ce que tu veux dire mais d'accord on en parle maintenant parce que ça me va"
        let system = spread(monologue, from: 0, step: 0.5)
        let mic = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 4, end: 7, text: "D'accord, oui, je vois, tu veux qu'on en parle."),
            Segment(id: 1, speaker: "Moi", channel: .mic, start: 8, end: 9, text: "Oui, ça marche."),
        ]
        let kept = TranscriptBuilder.removingEcho(mic: mic, systemWords: system)
        #expect(kept.map(\.id) == [0, 1])
    }

    @Test func fusionneLesCanauxDansLOrdreChronologique() {
        let a = [Segment(id: 0, speaker: "Moi", channel: .mic, start: 5, end: 6, text: "b")]
        let b = [Segment(id: 0, speaker: "Interlocuteur 1", channel: .system, start: 1, end: 2, text: "a")]
        let merged = TranscriptBuilder.merge([a, b])
        #expect(merged.map(\.text) == ["a", "b"])
        #expect(merged.map(\.id) == [0, 1])
    }

    @Test func intercaleUneInterventionAuMilieuDUnLongTour() {
        // L'autre parle 12 s en trois phrases ; j'interviens à 5 s.
        let long = spread("Première phrase assez longue. Deuxième phrase tout aussi longue. Troisième phrase pour finir.", from: 0, step: 1.0)
        let other = TranscriptBuilder.Run(speaker: "sys:S1", channel: .system, words: long)
        let mine = TranscriptBuilder.Run(
            speaker: "mic:S1", channel: .mic, words: words([("Attends,", 5.1, 5.4), ("une", 5.5, 5.6), ("question.", 5.7, 6.2)]))
        let result = TranscriptBuilder.interleave([other, mine])
        #expect(result.map(\.speaker) == ["sys:S1", "mic:S1", "sys:S1"])
        #expect(result[0].text == "Première phrase assez longue.")
        #expect(result[2].text.hasPrefix("Deuxième phrase"))
    }

    @Test func neCoupePasSansIntervention() {
        let long = spread("Une phrase. Puis une autre. Et une dernière.", from: 0, step: 0.5)
        let result = TranscriptBuilder.interleave([TranscriptBuilder.Run(speaker: "a", channel: .system, words: long)])
        #expect(result.count == 1)
    }

    @Test func numéroteDansLOrdreDIntervention() {
        let runs = [
            TranscriptBuilder.Run(speaker: "sys:S3", channel: .system, words: words([("Bonjour.", 0, 1)])),
            TranscriptBuilder.Run(speaker: "mic:S1", channel: .mic, words: words([("Salut.", 1, 2)])),
            TranscriptBuilder.Run(speaker: "sys:S1", channel: .system, words: words([("Hello.", 2, 3)])),
            TranscriptBuilder.Run(speaker: "sys:S3", channel: .system, words: words([("Bien.", 3, 4)])),
        ]
        let segments = TranscriptBuilder.segments(from: runs, me: ["mic:S1"])
        #expect(segments.map(\.speaker) == ["Interlocuteur 1", "Moi", "Interlocuteur 2", "Interlocuteur 1"])
    }

    @Test func recaleLeChangementDeVoixSurLaPause() {
        // « … pour performer encore plus | c'est le bouche à oreille » : la diarisation a coupé un mot trop tôt.
        let w = words([
            ("pour", 0.0, 0.2), ("performer", 0.2, 0.7), ("encore", 0.7, 1.0), ("plus", 1.0, 1.2),
            ("c'est", 1.9, 2.1), ("le", 2.1, 2.2), ("bouche", 2.2, 2.5), ("à", 2.5, 2.6), ("oreille", 2.6, 3.0),
        ])
        var labels = ["A", "A", "A", "B", "B", "B", "B", "B", "B"]
        TranscriptBuilder.snap(&labels, words: w)
        #expect(labels == ["A", "A", "A", "A", "B", "B", "B", "B", "B"])
    }

    @Test func recaleLeChangementDeVoixSurLaFinDePhrase() {
        // « … à la monnaie. Là on a | sorti quelques leviers » : les trois mots vont avec la suite.
        let w = words([
            ("à", 0.0, 0.1), ("la", 0.1, 0.2), ("monnaie.", 0.2, 0.7), ("Là", 0.75, 0.9), ("on", 0.9, 1.0),
            ("a", 1.0, 1.1), ("sorti", 1.1, 1.4), ("quelques", 1.4, 1.7), ("leviers", 1.7, 2.1),
        ])
        var labels = ["A", "A", "A", "A", "A", "A", "B", "B", "B"]
        TranscriptBuilder.snap(&labels, words: w)
        #expect(labels == ["A", "A", "A", "B", "B", "B", "B", "B", "B"])
    }

    @Test func laisseUneFrontièreDéjàBienPlacée() {
        let w = words([("Tu", 0, 0.2), ("viens", 0.2, 0.5), ("demain", 0.5, 0.9), ("?", 0.9, 1.0), ("Oui,", 1.6, 1.8), ("bien", 1.8, 2.0), ("sûr.", 2.0, 2.3)])
        var labels = ["A", "A", "A", "A", "B", "B", "B"]
        TranscriptBuilder.snap(&labels, words: w)
        #expect(labels == ["A", "A", "A", "A", "B", "B", "B"])
    }

    @Test func nommeMoiLeLocuteurReconnu() {
        let turns = [SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1, end: 2)]
        let names = TranscriptBuilder.names(for: turns, startingAt: 3, me: "S2")
        #expect(names == ["S1": "Interlocuteur 3", "S2": "Moi"])
    }
}

@Suite("Empreinte vocale et fusion des voix")
struct VoiceTests {
    @Test func reconnaîtLaVoixLaPlusProche() {
        let print = Voiceprint(embedding: [1, 0, 0], samples: 3)
        #expect(print.match(in: ["S1": [0, 1, 0], "S2": [0.9, 0.1, 0]]) == "S2")
        #expect(print.match(in: ["S1": [0, 1, 0]]) == nil)
    }

    @Test func gardeDistinctesDeuxVoixSeulementProches() {
        // Ressemblance d'environ 0,5 : deux personnes à la voix proche, pas la même personne.
        let output = DiarizationOutput(
            turns: [SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1, end: 2)],
            embeddings: ["S1": [1, 0, 0], "S2": [0.5, 0.866, 0]])
        #expect(SpeechEngine.mergingSimilarVoices(output).embeddings.count == 2)
    }

    @Test func retireUneVoixFantôme() {
        let output = DiarizationOutput(
            turns: [
                SpeakerTurn(speaker: "S1", start: 0, end: 300), SpeakerTurn(speaker: "S4", start: 300, end: 302),
                SpeakerTurn(speaker: "S2", start: 302, end: 600),
            ],
            embeddings: ["S1": [1, 0], "S2": [0, 1], "S4": [0.7, 0.7]])
        let cleaned = SpeechEngine.removingPhantomVoices(output)
        #expect(cleaned.turns.map(\.speaker) == ["S1", "S2"])
        #expect(cleaned.embeddings["S4"] == nil)
    }

    @Test func fusionneDeuxVoixQuasiIdentiques() {
        let output = DiarizationOutput(
            turns: [
                SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1.1, end: 2),
                SpeakerTurn(speaker: "S3", start: 3, end: 4),
            ],
            embeddings: ["S1": [1, 0, 0], "S2": [0.9, 0.2, 0], "S3": [0, 0, 1]])
        let merged = SpeechEngine.mergingSimilarVoices(output)
        #expect(Set(merged.embeddings.keys) == ["S1", "S3"])
        #expect(merged.turns.map(\.speaker) == ["S1", "S3"])
        #expect(merged.turns[0].end == 2)
    }

    @Test func laisseDeuxVoixDistinctes() {
        let output = DiarizationOutput(
            turns: [SpeakerTurn(speaker: "S1", start: 0, end: 1), SpeakerTurn(speaker: "S2", start: 1, end: 2)],
            embeddings: ["S1": [1, 0], "S2": [0.2, 1]])
        #expect(SpeechEngine.mergingSimilarVoices(output).embeddings.count == 2)
    }
}

@Suite("Bibliothèque")
struct LibraryTests {
    func makeStore() -> TranscriptStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        return TranscriptStore(root: root)
    }

    func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)!
    }

    @Test func enregistreListeEtRecherche() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = date("2026-10-01 09:00:00")
        let second = date("2026-10-02 14:31:05")
        try store.save(
            Transcript(
                id: store.makeID(for: first), createdAt: first, mode: .dictation, duration: 12, engine: "test",
                text: "Rappeler le plombier demain.", rawText: "rappeler le plombier demain"))
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 2, text: "On valide le budget ?"),
            Segment(id: 1, speaker: "Interlocuteur 1", channel: .system, start: 2, end: 4, text: "Oui, validé."),
        ]
        try store.save(
            Transcript(
                id: store.makeID(for: second), createdAt: second, mode: .meeting, duration: 60, engine: "test",
                text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments,
                speakers: ["Moi", "Interlocuteur 1"]))

        #expect(store.list().map(\.id) == ["2026-10-02_14-31-05", "2026-10-01_09-00-00"])
        #expect(store.latest()?.mode == .meeting)
        #expect(store.latest(mode: .dictation)?.id == "2026-10-01_09-00-00")
        #expect(store.search("PLOMBIER").count == 1)
        #expect(store.search("valide budget").map(\.id) == ["2026-10-02_14-31-05"])
        #expect(store.search("introuvable").isEmpty)

        let latest = try String(contentsOf: store.root.appendingPathComponent("dernier.md"), encoding: .utf8)
        #expect(latest.contains("**Interlocuteur 1** [0:02] : Oui, validé."))
        let index = try String(contentsOf: store.root.appendingPathComponent("index.jsonl"), encoding: .utf8)
        #expect(index.split(separator: "\n").count == 2)
    }

    @Test func deuxIdentifiantsRéservésAvantÉcritureSontDistincts() {
        let store = makeStore()
        let moment = date("2026-10-02 12:00:00")
        let ids = (0..<3).map { _ in store.makeID(for: moment) }
        #expect(Set(ids).count == 3)
    }

    @Test func deuxIdentifiantsDansLaMêmeSecondeRestentOrdonnés() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let moment = date("2026-10-02 10:00:00")
        let a = store.makeID(for: moment)
        try store.save(Transcript(id: a, createdAt: moment, mode: .dictation, duration: 1, engine: "t", text: "un", rawText: ""))
        let b = store.makeID(for: moment)
        try store.save(Transcript(id: b, createdAt: moment, mode: .dictation, duration: 1, engine: "t", text: "deux", rawText: ""))
        #expect(a != b)
        #expect(store.list().map(\.text) == ["deux", "un"])
    }

    @Test func renommeUnInterlocuteur() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let moment = date("2026-10-02 11:00:00")
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 1, text: "Salut."),
            Segment(id: 1, speaker: "Interlocuteur 1", channel: .system, start: 1, end: 2, text: "Salut."),
        ]
        let id = store.makeID(for: moment)
        try store.save(
            Transcript(
                id: id, createdAt: moment, mode: .meeting, duration: 2, engine: "t",
                text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments,
                speakers: ["Moi", "Interlocuteur 1"]))
        let renamed = try store.renameSpeaker(id: id, from: "Interlocuteur 1", to: "Victor")
        #expect(renamed?.speakers == ["Moi", "Victor"])
        #expect(store.load(id: id)?.text.contains("Victor [0:01] : Salut.") == true)
    }
}

@Suite("Reprise des enregistrements interrompus")
struct RecoveryTests {
    @Test func repèreLAudioSansTranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID().uuidString)")
        let store = TranscriptStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try store.ensureDirectory(forID: "2026-10-02_10-00-00")
        let silence = [Float](repeating: 0, count: 1600)
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_10-00-00_mic.wav"))
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_10-00-00_sys.wav"))
        Recovery.stash(silence, at: try Recovery.dictationURL(id: "2026-10-02_11-00-00", store: store))
        // Celui-ci a déjà son transcript : il ne doit pas être repris.
        Recovery.stash(silence, at: directory.appendingPathComponent("2026-10-02_12-00-00_mic.wav"))
        try store.save(
            Transcript(
                id: "2026-10-02_12-00-00", createdAt: Date(), mode: .meeting, duration: 1, engine: "t", text: "x",
                rawText: ""))

        let pending = Recovery.pending(in: store)
        #expect(pending.map(\.id) == ["2026-10-02_10-00-00", "2026-10-02_11-00-00"])
        #expect(pending[0].mode == .meeting)
        #expect(pending[0].system != nil)
        #expect(pending[1].mode == .dictation)
        #expect(Recovery.pending(in: store, excluding: ["2026-10-02_10-00-00"]).count == 1)
        #expect(TranscriptStore.date(fromID: "2026-10-02_10-00-00b") != nil)
    }
}

@Suite("Statistiques")
struct StatsTests {
    func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    func dictation(_ day: String, words: Int, seconds: Double) -> Transcript {
        Transcript(
            id: day, createdAt: date(day), mode: .dictation, duration: seconds, engine: "t",
            text: Array(repeating: "mot", count: words).joined(separator: " "), rawText: "")
    }

    @Test func totauxDébitEtTempsGagné() {
        let now = date("2026-10-02 18:00")
        let stats = LibraryStats(
            transcripts: [
                dictation("2026-10-02 09:00", words: 300, seconds: 120),
                dictation("2026-10-01 09:00", words: 100, seconds: 60),
                dictation("2026-09-20 09:00", words: 50, seconds: 30),
            ], now: now)
        #expect(stats.transcripts == 3)
        #expect(stats.words == 450)
        #expect(stats.wordsThisWeek == 400)
        // 450 mots en 210 s : 129 mots par minute.
        #expect(stats.wordsPerMinute == 129)
        // À 40 mots par minute, 450 mots demandent 675 s de frappe ; 210 s de parole.
        #expect(stats.timeSaved == 465)
        #expect(stats.streak == 2)
        #expect(stats.days.count == 371)
        #expect(stats.days.last?.words == 300)
        #expect(stats.wordsToday == 300)
        #expect(stats.bestDay?.words == 300)
        #expect(stats.bestStreak == 2)
        #expect(stats.days.reduce(0) { $0 + $1.words } == 450)
    }

    @Test func laSérieTientSiRienNAÉtéDictéAujourdHui() {
        let stats = LibraryStats(
            transcripts: [dictation("2026-10-01 09:00", words: 10, seconds: 5), dictation("2026-09-30 09:00", words: 10, seconds: 5)],
            now: date("2026-10-02 08:00"))
        #expect(stats.streak == 2)
        let broken = LibraryStats(
            transcripts: [dictation("2026-09-29 09:00", words: 10, seconds: 5)], now: date("2026-10-02 08:00"))
        #expect(broken.streak == 0)
    }

    @Test func enRéunionSeulsMesMotsComptent() {
        let segments = [
            Segment(id: 0, speaker: "Moi", channel: .mic, start: 0, end: 1, text: "un deux trois"),
            Segment(id: 1, speaker: "Interlocuteur 1", channel: .system, start: 1, end: 2, text: "quatre cinq six sept"),
        ]
        let meeting = Transcript(
            id: "m", createdAt: date("2026-10-02 10:00"), mode: .meeting, duration: 60, engine: "t",
            text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments,
            speakers: ["Moi", "Interlocuteur 1"])
        let stats = LibraryStats(transcripts: [meeting], now: date("2026-10-02 18:00"))
        #expect(stats.words == 3)
        #expect(stats.meetings == 1)
        #expect(stats.wordsPerMinute == 0)
    }
}

@Suite("Formats")
struct FormatTests {
    @Test func durées() {
        #expect(Format.clock(65) == "1:05")
        #expect(Format.clock(3723) == "1:02:03")
        #expect(Format.duration(45) == "45 s")
        #expect(Format.duration(725) == "12 min 05 s")
        #expect(Format.duration(3720) == "1 h 02 min")
    }

    @Test func modesDepuisLeurNom() {
        #expect(RecordingMode(slug: "reunion") == .meeting)
        #expect(RecordingMode(slug: "Dictée") == .dictation)
        #expect(RecordingMode(slug: "autre") == nil)
    }
}
