import CoreML
import FluidAudio
import Foundation

/// Modèles de transcription disponibles. Ajouter un cas ici suffit à l'exposer dans les réglages.
public enum EngineModel: String, CaseIterable, Codable, Sendable {
    /// Parakeet Ultra : ré-entraînement 2026 de Parakeet TDT v3, 25 langues européennes,
    /// le plus précis en français parmi les modèles temps réel embarquables.
    case parakeetUltra = "parakeet-ultra"
    /// Parakeet TDT v3 d'origine (NVIDIA).
    case parakeetV3 = "parakeet-v3"

    public var label: String {
        switch self {
        case .parakeetUltra: return "Parakeet Ultra (recommandé)"
        case .parakeetV3: return "Parakeet TDT v3"
        }
    }

    var version: AsrModelVersion {
        switch self {
        case .parakeetUltra: return .ultra
        case .parakeetV3: return .v3
        }
    }
}

public struct EngineOutput: Sendable {
    public var text: String
    public var words: [Word]
    public var duration: Double
    public var processing: Double
}

/// Intervalle de parole attribué à un locuteur par la diarisation.
public struct SpeakerTurn: Sendable, Equatable {
    public var speaker: String
    public var start: Double
    public var end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

public struct DiarizationOutput: Sendable {
    public var turns: [SpeakerTurn]
    /// Empreinte vocale moyenne par locuteur (vecteur normalisé).
    public var embeddings: [String: [Float]]
}

public enum EngineError: LocalizedError {
    case notReady

    public var errorDescription: String? {
        switch self {
        case .notReady: return "Le modèle de transcription n'est pas encore chargé."
        }
    }
}

// Les modèles CoreML du diariseur sont en lecture seule après chargement ; l'acteur sérialise le reste.
extension OfflineDiarizerManager: @retroactive @unchecked Sendable {}

public enum EngineLoadPhase: Sendable {
    case downloading(Double)
    case compiling
    case ready
}

/// Moteur de reconnaissance vocale 100 % local (CoreML, Neural Engine).
public actor SpeechEngine {
    public static let shared = SpeechEngine()
    public static let sampleRate = 16_000

    private var asr: AsrManager?
    private var loadedModel: EngineModel?
    private var loadTask: Task<Void, Error>?
    private var diarizer: OfflineDiarizerManager?
    private var fixedDiarizers: [Int: OfflineDiarizerManager] = [:]
    private var diarizerModels: OfflineDiarizerModels?
    private var diarizerTask: Task<OfflineDiarizerModels, Error>?
    private var echoCanceller: LocalVqeManager?

    public init() {}

    public var isReady: Bool { asr != nil }
    public var modelName: String { loadedModel?.rawValue ?? "—" }

    /// Charge le modèle (le télécharge au premier lancement, ~600 Mo).
    public func prepare(
        model: EngineModel, progress: (@Sendable (EngineLoadPhase) -> Void)? = nil
    ) async throws {
        if loadedModel == model, asr != nil { return }
        if let loadTask {
            try await loadTask.value
            if loadedModel == model { return }
        }
        let task = Task {
            let models = try await AsrModels.downloadAndLoad(
                version: model.version,
                progressHandler: { p in
                    switch p.phase {
                    case .listing: progress?(.downloading(0))
                    case .downloading: progress?(.downloading(p.fractionCompleted))
                    case .compiling: progress?(.compiling)
                    }
                })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.install(manager, model: model)
            progress?(.ready)
        }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    private func install(_ manager: AsrManager, model: EngineModel) {
        asr = manager
        loadedModel = model
    }

    /// Libère les modèles (plusieurs centaines de Mo). Ils se rechargent depuis le cache
    /// disque, en une fraction de seconde, au prochain `prepare`.
    public func unload() {
        guard loadTask == nil, diarizerTask == nil else { return }
        asr = nil
        loadedModel = nil
        diarizer = nil
        fixedDiarizers = [:]
        diarizerModels = nil
        echoCanceller = nil
    }

    // MARK: - Annulation d'écho

    /// Retire du micro le son de l'ordinateur que les haut-parleurs y ont renvoyé (réunion
    /// sans casque). `reference` est ce son, sur la même ligne de temps et de même longueur.
    ///
    /// Le signal nettoyé n'est utilisé que là où l'ordinateur émettait quelque chose : partout
    /// ailleurs le micro d'origine est conservé tel quel, pour ne pas altérer la voix.
    public func cancelEcho(mic: [Float], reference: [Float]) async throws -> [Float] {
        guard mic.count == reference.count, !mic.isEmpty else { return mic }
        let active = Self.activityMask(reference)
        guard active.contains(true) else { return mic }
        if echoCanceller == nil {
            echoCanceller = try await LocalVqeManager()
        }
        guard let echoCanceller else { return mic }
        let cleaned = try await echoCanceller.process(mic: mic, reference: reference)
        guard cleaned.count == mic.count else { return mic }

        // Fondu d'une trame à l'autre entre micro d'origine et micro nettoyé.
        let frame = Self.maskFrame
        var output = mic
        var weight: Float = 0
        let step = 1 / Float(frame / 2)
        for i in 0..<mic.count {
            let target: Float = active[min(i / frame, active.count - 1)] ? 1 : 0
            if weight < target { weight = min(target, weight + step) }
            if weight > target { weight = max(target, weight - step) }
            output[i] = mic[i] * (1 - weight) + cleaned[i] * weight
        }
        return output
    }

    static let maskFrame = sampleRate / 10

    /// Par trames de 100 ms : vrai si la référence porte du son, avec une marge d'une demi-seconde
    /// de part et d'autre (réverbération de la pièce, léger décalage entre les canaux).
    static func activityMask(_ reference: [Float], threshold: Float = 0.002) -> [Bool] {
        let frame = maskFrame
        let count = (reference.count + frame - 1) / frame
        var loud = [Bool](repeating: false, count: count)
        for index in 0..<count {
            let start = index * frame
            let end = min(start + frame, reference.count)
            loud[index] = AudioLevel.rms(reference[start..<end]) > threshold
        }
        var mask = loud
        let margin = 5
        for index in 0..<count where loud[index] {
            for neighbour in max(0, index - margin)...min(count - 1, index + margin) { mask[neighbour] = true }
        }
        return mask
    }

    /// Transcrit des échantillons mono 16 kHz. Gère l'audio long (découpage interne).
    public func transcribe(_ samples: [Float]) async throws -> EngineOutput {
        guard let asr else { throw EngineError.notReady }
        var audio = samples
        // Le modèle refuse moins de 300 ms : on complète par du silence.
        let minimum = Self.sampleRate
        if audio.count < minimum {
            audio.append(contentsOf: [Float](repeating: 0, count: minimum - audio.count))
        }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(audio, decoderState: &state)
        let words = Self.words(from: result.tokenTimings ?? [])
        return EngineOutput(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            words: words,
            duration: Double(samples.count) / Double(Self.sampleRate),
            processing: result.processingTime
        )
    }

    /// Mots horodatés. Une ponctuation isolée (« ? », « ! », « : » à la française) est
    /// rattachée au mot qui précède, pour ne jamais ouvrir un tour de parole.
    static func words(from timings: [TokenTiming]) -> [Word] {
        var words: [Word] = []
        for timing in buildWordTimings(from: timings) {
            let isPunctuation = timing.word.allSatisfy { ".,;:!?…»".contains($0) }
            if isPunctuation, var last = words.popLast() {
                let separator = timing.word.first.map { "?!:;»".contains($0) } == true ? " " : ""
                last.text += separator + timing.word
                last.end = timing.endTime
                words.append(last)
            } else {
                words.append(Word(text: timing.word, start: timing.startTime, end: timing.endTime))
            }
        }
        return words
    }

    // MARK: - Diarisation

    /// Diariseur pour un nombre de voix donné (`nil` : détection automatique). Les modèles
    /// ne sont chargés qu'une fois ; seule la configuration du regroupement change.
    private func loadDiarizer(speakers: Int? = nil) async throws -> OfflineDiarizerManager {
        if speakers == nil, let diarizer { return diarizer }
        if let speakers, let manager = fixedDiarizers[speakers] { return manager }
        if diarizerModels == nil {
            if let diarizerTask {
                diarizerModels = try await diarizerTask.value
            } else {
                let task = Task { try await OfflineDiarizerModels.load() }
                diarizerTask = task
                defer { diarizerTask = nil }
                diarizerModels = try await task.value
            }
        }
        guard let models = diarizerModels else { throw EngineError.notReady }
        var config = OfflineDiarizerConfig.default
        config.clustering.threshold = Self.clusteringThreshold
        config.clustering.numSpeakers = speakers
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        if let speakers { fixedDiarizers[speakers] = manager } else { diarizer = manager }
        return manager
    }

    /// Précharge les modèles de diarisation (téléchargement au premier usage).
    public func prepareDiarizer() async throws {
        _ = try await loadDiarizer()
    }

    /// « Qui parle quand » sur des échantillons mono 16 kHz.
    /// - Parameter speakers: nombre de voix imposé, quand l'utilisateur le connaît.
    public func diarize(
        _ samples: [Float], speakers: Int? = nil, mergeSimilar: Bool = true
    ) async throws -> DiarizationOutput {
        // En dessous de deux secondes la diarisation n'a pas de sens.
        guard samples.count >= Self.sampleRate * 2 else {
            return DiarizationOutput(turns: [], embeddings: [:])
        }
        let manager = try await loadDiarizer(speakers: speakers)
        let result = try await manager.process(audio: samples)
        let turns = result.segments
            .map {
                SpeakerTurn(
                    speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
            }
            .sorted { $0.start < $1.start }
        let output = Self.removingPhantomVoices(
            DiarizationOutput(turns: turns, embeddings: result.speakerDatabase ?? [:]))
        // Quand le nombre de voix est imposé, on ne refusionne rien derrière.
        return mergeSimilar && speakers == nil ? Self.mergingSimilarVoices(output) : output
    }

    /// Seuil de regroupement des voix (distance) : plus il est bas, plus le diariseur sépare.
    static let clusteringThreshold: Double =
        ProcessInfo.processInfo.environment["PLUME_DIAR_THRESHOLD"].flatMap(Double.init) ?? 0.6

    /// Ressemblance au-delà de laquelle deux voix détectées sont tenues pour la même personne.
    static let sameVoiceSimilarity: Float =
        ProcessInfo.processInfo.environment["PLUME_SAME_VOICE"].flatMap(Float.init) ?? 0.72

    /// Retire les voix fantômes : un « locuteur » qui ne parle que quelques secondes sur toute
    /// une réunion est presque toujours un bruit ou un éclat de voix mal classé. Ses mots
    /// reviennent alors au locuteur voisin.
    static func removingPhantomVoices(_ output: DiarizationOutput) -> DiarizationOutput {
        var talk: [String: Double] = [:]
        for turn in output.turns { talk[turn.speaker, default: 0] += turn.end - turn.start }
        let total = talk.values.reduce(0, +)
        guard talk.count > 1, total > 0 else { return output }
        let phantoms = Set(talk.filter { $0.value < 6 && $0.value < total * 0.02 }.keys)
        guard !phantoms.isEmpty, phantoms.count < talk.count else { return output }
        return DiarizationOutput(
            turns: output.turns.filter { !phantoms.contains($0.speaker) },
            embeddings: output.embeddings.filter { !phantoms.contains($0.key) })
    }

    /// Le regroupement automatique coupe parfois une même voix en deux. On ne refusionne que
    /// des empreintes quasi identiques : deux personnes à la voix proche (deux frères, par
    /// exemple) atteignent couramment 0,5 de ressemblance et doivent rester distinctes.
    static func mergingSimilarVoices(_ output: DiarizationOutput) -> DiarizationOutput {
        let ids = output.embeddings.keys.sorted()
        guard ids.count > 1 else { return output }
        var parent = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        func root(_ id: String) -> String {
            var current = id
            while let next = parent[current], next != current { current = next }
            return current
        }
        for (index, a) in ids.enumerated() {
            for b in ids[(index + 1)...] {
                let similarity = Voiceprint.cosine(output.embeddings[a] ?? [], output.embeddings[b] ?? [])
                if similarity >= sameVoiceSimilarity {
                    parent[root(b)] = root(a)
                }
            }
        }
        guard ids.contains(where: { root($0) != $0 }) else { return output }

        // Empreinte du groupe : moyenne des empreintes fusionnées.
        var embeddings: [String: [Float]] = [:]
        var counts: [String: Float] = [:]
        for id in ids {
            guard let vector = output.embeddings[id] else { continue }
            let key = root(id)
            if var sum = embeddings[key], sum.count == vector.count {
                for i in 0..<sum.count { sum[i] += vector[i] }
                embeddings[key] = sum
            } else {
                embeddings[key] = vector
            }
            counts[key, default: 0] += 1
        }
        for (key, count) in counts where count > 1 {
            embeddings[key] = embeddings[key]?.map { $0 / count }
        }

        // Tours consécutifs du même locuteur recollés.
        var turns: [SpeakerTurn] = []
        for turn in output.turns {
            let speaker = parent[turn.speaker] == nil ? turn.speaker : root(turn.speaker)
            if let last = turns.last, last.speaker == speaker, turn.start - last.end < 0.5 {
                turns[turns.count - 1].end = max(last.end, turn.end)
            } else {
                turns.append(SpeakerTurn(speaker: speaker, start: turn.start, end: turn.end))
            }
        }
        return DiarizationOutput(turns: turns, embeddings: embeddings)
    }
}
