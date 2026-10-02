import AVFoundation
import AppKit
import PlumeKit

/// Chef d'orchestre d'un enregistrement : capture, transcription en direct,
/// traitement final, collage et rangement dans la bibliothèque.
@MainActor
final class SessionController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing(String)
        case done(String)
        case failed(String)
    }

    enum ModelStatus: Equatable {
        case loading(Double?)
        case ready
        case failed(String)
    }

    static let levelCount = 30

    @Published private(set) var phase: Phase = .idle
    /// Dernier état non inactif : la pastille garde son contenu pendant qu'elle disparaît.
    @Published private(set) var displayPhase: Phase = .idle
    @Published private(set) var mode: RecordingMode = .dictation
    @Published private(set) var elapsed: TimeInterval = 0
    /// Niveaux sonores récents du micro (0…1), du plus ancien au plus récent.
    @Published private(set) var levels = [Float](repeating: 0, count: levelCount)
    /// Vrai quand le son de l'ordinateur porte de la parole (réunion).
    @Published private(set) var systemActive = false
    @Published private(set) var liveCommitted = ""
    @Published private(set) var liveVolatile = ""
    @Published private(set) var modelStatus: ModelStatus = .loading(nil)
    /// Dernier transcript produit, ouvrable depuis la pastille.
    @Published private(set) var lastTranscript: Transcript?

    var onLibraryChanged: (() -> Void)?
    var onPhaseChanged: ((Phase) -> Void)?
    var onModeChanged: ((RecordingMode) -> Void)?

    private let settings = PlumeSettings.shared
    private let engine = SpeechEngine.shared
    private var mic: AudioSource?
    private var system: AudioSource?
    private var micChannel: ChannelRecorder?
    private var systemChannel: ChannelRecorder?
    private var sessionID: String?
    private var startedAt: Date?
    private var frontApp: String?
    private var clock: Timer?
    private var liveTask: Task<Void, Never>?
    private var micLive: LiveTranscriber?
    private var systemLive: LiveTranscriber?
    private var hideTask: Task<Void, Never>?
    private var startedByCurrentPress = false
    private var unloadTask: Task<Void, Never>?
    /// Délai d'inactivité après lequel les modèles sont retirés de la mémoire.
    private static let idleUnloadDelay: TimeInterval =
        ProcessInfo.processInfo.environment["PLUME_IDLE_UNLOAD"].flatMap(TimeInterval.init) ?? 600
    /// Empêche la mise en veille automatique pendant qu'une réunion s'enregistre.
    private var awake: NSObjectProtocol?
    private var systemActiveUntil = Date.distantPast

    private var askedForAccessibility = false
    /// Annulation d'un faux déclenchement (⌃⇧ suivi d'une touche) : pas de son.
    private var silentCancel = false
    /// Sessions en cours d'enregistrement ou de traitement : la reprise ne doit pas y toucher.
    private var activeSessions = Set<String>()
    /// Imports de fichiers en cours (glisser-déposer, menu).
    private var imports = 0
    private var importing: Bool { imports > 0 }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool {
        if case .processing = phase { return true }
        return phase == .recording
    }

    // MARK: - Modèle

    func loadModel() {
        modelStatus = .loading(nil)
        let model = settings.model
        Task {
            do {
                try await engine.prepare(model: model) { [weak self] phase in
                    Task { @MainActor in
                        guard let self, self.modelStatus != .ready else { return }
                        switch phase {
                        case .downloading(let fraction): self.modelStatus = .loading(fraction)
                        case .compiling: self.modelStatus = .loading(nil)
                        case .ready: self.modelStatus = .ready
                        }
                    }
                }
                modelStatus = .ready
                if phase == .idle { scheduleUnload() }
                recoverInterruptedSessions()
            } catch {
                modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Raccourcis

    func handlePress(_ action: HotkeyAction) {
        guard let requested = action.mode else { return }
        switch phase {
        case .recording:
            startedByCurrentPress = false
            if action == .dictation || mode == requested {
                // Le raccourci principal termine toujours l'enregistrement en cours.
                stop()
            } else {
                switchMode(to: requested)
            }
        case .processing:
            break
        case .idle, .done, .failed:
            startedByCurrentPress = true
            start(requested)
        }
    }

    /// Relâchement : si la touche a été tenue, c'était un « parler en maintenant ».
    func handleRelease(_ action: HotkeyAction, held: TimeInterval) {
        defer { startedByCurrentPress = false }
        guard startedByCurrentPress, phase == .recording, mode == .dictation, action == .dictation,
            held >= 0.7
        else { return }
        stop()
    }

    /// Le maintien s'est révélé être un autre raccourci clavier : on jette l'enregistrement.
    func handleCancel(_ action: HotkeyAction) {
        guard startedByCurrentPress, phase == .recording, mode == action.mode else { return }
        silentCancel = true
        startedByCurrentPress = false
        cancel()
    }

    func toggle(_ mode: RecordingMode) {
        if phase == .recording {
            if self.mode == mode { stop() } else { switchMode(to: mode) }
        } else {
            start(mode)
        }
    }

    // MARK: - Démarrage

    func start(_ mode: RecordingMode) {
        guard !isBusy else { return }
        switch TestHooks.fakeMic == nil ? AVCaptureDevice.authorizationStatus(for: .audio) : .authorized {
        case .notDetermined:
            let asked = Date()
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard granted else {
                        self?.finish(.failed("Micro non autorisé"))
                        return
                    }
                    // Réponse immédiate : on enchaîne. Sinon l'intention est passée, on ne
                    // démarre pas un enregistrement dans le dos de l'utilisateur.
                    if Date().timeIntervalSince(asked) < 20 {
                        self?.start(mode)
                    } else {
                        self?.finish(.done("Micro autorisé"), hideAfter: 2)
                    }
                }
            }
            return
        case .denied, .restricted:
            finish(.failed("Micro non autorisé"))
            Permissions.openSettings(.microphone)
            return
        default:
            break
        }

        hideTask?.cancel()
        // Le modèle a pu être déchargé pendant l'inactivité : on le recharge dès maintenant,
        // pendant que l'utilisateur commence à parler.
        unloadTask?.cancel()
        let engine = self.engine
        let model = settings.model
        Task { try? await engine.prepare(model: model) }

        let now = Date()
        let store = settings.store
        let id = store.makeID(for: now)
        // Une réunion est écrite sur disque au fil de l'eau : rien n'est perdu si l'app s'arrête.
        let directory = mode == .meeting ? try? store.ensureDirectory(forID: id) : nil

        let micRecorder = ChannelRecorder(channel: .mic, sessionStart: now)
        if let directory, let writer = try? WavWriter(url: directory.appendingPathComponent("\(id)_mic.wav")) {
            micRecorder.attach(writer)
        }
        micRecorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.pushLevel(level) }
        }
        let capture: AudioSource = TestHooks.fakeMic.map { FileCapture(url: $0) } ?? MicCapture()
        capture.onSamples = { micRecorder.append($0) }
        // Micro perdu en route : on termine proprement avec ce qui a été capté.
        (capture as? MicCapture)?.onFailure = { [weak self] in
            Task { @MainActor in self?.stop() }
        }
        do {
            try capture.start()
        } catch {
            micRecorder.writer?.close()
            finish(.failed("Micro indisponible"))
            return
        }
        mic = capture
        micChannel = micRecorder
        if let microphone = capture as? MicCapture { Log.write("micro : « \(microphone.deviceName) »") }

        self.mode = mode
        startedAt = now
        if mode == .meeting { startSystemCapture(id: id, directory: directory, sessionStart: now) }

        sessionID = id
        activeSessions.insert(id)
        let front = NSWorkspace.shared.frontmostApplication?.localizedName
        frontApp = front == "loginwindow" ? nil : front
        elapsed = 0
        levels = [Float](repeating: 0, count: Self.levelCount)
        liveCommitted = ""
        liveVolatile = ""
        systemActive = false
        setPhase(.recording)
        Sounds.play(.start)
        if mode == .meeting { keepAwake(true) }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                self.systemActive = Date() < self.systemActiveUntil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        startLive()
    }

    private func pushLevel(_ rms: Float) {
        // Échelle logarithmique : -55 dB → 0, -12 dB → 1.
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, min(1, (db + 55) / 43))
        levels.removeFirst()
        levels.append(normalized)
    }

    /// Capte le son de l'ordinateur sur un second canal (mode réunion).
    private func startSystemCapture(id: String, directory: URL?, sessionStart: Date) {
        guard settings.systemAudioInMeeting, system == nil else { return }
        let recorder = ChannelRecorder(channel: .system, sessionStart: sessionStart)
        if let directory, let writer = try? WavWriter(url: directory.appendingPathComponent("\(id)_sys.wav")) {
            recorder.attach(writer)
        }
        recorder.onLevel = { [weak self] level in
            guard level > 0.006 else { return }
            DispatchQueue.main.async { self?.systemActiveUntil = Date().addingTimeInterval(0.6) }
        }
        let tap: AudioSource = TestHooks.fakeSystem.map { FileCapture(url: $0) } ?? SystemAudioCapture()
        tap.onSamples = { recorder.append($0) }
        // Si la capture échoue ou n'est pas autorisée, le canal reste vide et la réunion
        // continue avec le micro seul.
        try? tap.start()
        system = tap
        systemChannel = recorder
        if settings.liveTranscript {
            systemLive = LiveTranscriber(engine: engine, buffer: recorder.buffer)
        }
    }

    private func keepAwake(_ on: Bool) {
        if on, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Enregistrement d'une réunion")
        } else if !on, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
        }
    }

    /// Passe de la dictée à la réunion (ou l'inverse) sans interrompre l'enregistrement.
    func switchMode(to newMode: RecordingMode) {
        guard phase == .recording, newMode != mode, newMode != .imported,
            let micChannel, let sessionID, let startedAt
        else { return }
        if newMode == .meeting {
            // À partir d'ici l'audio est écrit sur disque au fil de l'eau, début compris.
            let directory = try? settings.store.ensureDirectory(forID: sessionID)
            if micChannel.writer == nil, let directory,
                let writer = try? WavWriter(url: directory.appendingPathComponent("\(sessionID)_mic.wav"))
            {
                micChannel.attach(writer)
            }
            startSystemCapture(id: sessionID, directory: directory, sessionStart: startedAt)
            keepAwake(true)
        } else {
            system?.stop()
            system = nil
            systemLive = nil
            systemChannel?.writer?.close()
            if let url = systemChannel?.writer?.url { try? FileManager.default.removeItem(at: url) }
            systemChannel = nil
            systemActive = false
            keepAwake(false)
        }
        mode = newMode
        Sounds.play(newMode == .meeting ? .meetingOn : .meetingOff)
        TestHooks.log("mode : \(newMode)")
        onModeChanged?(newMode)
    }

    private func startLive() {
        guard settings.liveTranscript, let micChannel else { return }
        let engine = self.engine
        let model = settings.model
        micLive = LiveTranscriber(engine: engine, buffer: micChannel.buffer)
        liveTask = Task { [weak self] in
            try? await engine.prepare(model: model)
            while !Task.isCancelled {
                // Relus à chaque passe : le canal système peut apparaître en cours de route.
                guard let self, let micLive = self.micLive else { return }
                let systemLive = self.systemLive
                if let state = await micLive.tick(), !Task.isCancelled {
                    self.showLive(state)
                }
                if let systemLive, let state = await systemLive.tick(), !Task.isCancelled,
                    !state.volatile.isEmpty
                {
                    self.showLive(state)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func showLive(_ state: LiveTranscriber.State) {
        guard phase == .recording else { return }
        TestHooks.log("direct : …\(state.committed.suffix(40)) ▸ \(state.volatile)")
        liveCommitted = state.committed
        // Le modèle clôt toujours la fenêtre par un point : on ne l'affiche pas tant que ça bouge.
        var volatile = state.volatile
        while let last = volatile.last, ".…".contains(last) { volatile.removeLast() }
        liveVolatile = volatile
    }

    // MARK: - Arrêt

    private func teardownCapture() {
        mic?.stop()
        system?.stop()
        mic = nil
        system = nil
        clock?.invalidate()
        clock = nil
        liveTask?.cancel()
        liveTask = nil
        micLive = nil
        systemLive = nil
        micChannel?.writer?.close()
        systemChannel?.writer?.close()
        keepAwake(false)
    }

    private func removeTemporaryAudio() {
        for recorder in [micChannel, systemChannel] {
            if let url = recorder?.writer?.url { try? FileManager.default.removeItem(at: url) }
        }
    }

    func cancel() {
        guard phase == .recording else { return }
        teardownCapture()
        removeTemporaryAudio()
        if let sessionID { activeSessions.remove(sessionID) }
        micChannel = nil
        systemChannel = nil
        if !silentCancel { Sounds.play(.cancel) }
        silentCancel = false
        setPhase(.idle)
    }

    func stop() {
        guard phase == .recording, let micChannel, let sessionID, let startedAt else { return }
        let duration = Date().timeIntervalSince(startedAt)
        // Appui accidentel : rien à transcrire.
        guard duration >= 0.4 else {
            teardownCapture()
            removeTemporaryAudio()
            activeSessions.remove(sessionID)
            self.micChannel = nil
            systemChannel = nil
            setPhase(.idle)
            return
        }
        setPhase(.processing("Transcription"))
        let mode = self.mode
        let systemChannel = self.systemChannel
        let app = frontApp
        let stoppedAt = Date()
        // On laisse le micro ouvert un court instant : la dernière syllabe est souvent encore
        // en route quand on relâche le raccourci.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            teardownCapture()
            Sounds.play(.stop)
            self.micChannel = nil
            self.systemChannel = nil
            Task {
                if mode == .dictation {
                    // Une dictée repassée par le mode réunion a laissé un fichier de secours : inutile.
                    if let url = micChannel.writer?.url { try? FileManager.default.removeItem(at: url) }
                    await finishDictation(
                        id: sessionID, date: startedAt, duration: duration, samples: micChannel.buffer.all(),
                        app: app, stoppedAt: stoppedAt)
                } else {
                    await finishMeeting(
                        id: sessionID, date: startedAt, duration: duration, mic: micChannel, system: systemChannel)
                }
            }
        }
    }

    /// Fermeture de l'app en plein enregistrement : une réunion garde ses fichiers audio, qui
    /// seront transcrits au prochain lancement ; une dictée est abandonnée.
    func shutdown() {
        guard phase == .recording else { return }
        if mode == .meeting {
            teardownCapture()
        } else {
            cancel()
        }
    }

    /// Termine les enregistrements restés sans transcript (arrêt brutal, modèle indisponible).
    func recoverInterruptedSessions() {
        let settings = self.settings
        let active = activeSessions
        Task {
            let pending = await Task.detached { Recovery.pending(in: settings.store, excluding: active) }.value
            guard !pending.isEmpty else { return }
            imports += 1
            unloadTask?.cancel()
            defer {
                imports -= 1
                if phase == .idle { scheduleUnload() }
            }
            for item in pending {
                do {
                    if let transcript = try await Recovery.recover(item) {
                        Log.write("enregistrement repris : \(transcript.id)")
                        lastTranscript = transcript
                        onLibraryChanged?()
                    }
                } catch {
                    Log.write("reprise impossible (\(item.id)) : \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishDictation(
        id: String, date: Date, duration: Double, samples: [Float], app: String?, stoppedAt: Date
    ) async {
        defer { activeSessions.remove(id) }
        do {
            try await engine.prepare(model: settings.model)
            modelStatus = .ready
            let result = try await Pipeline.dictation(samples: samples, engine: engine, cleanup: settings.cleanup)
            guard !result.text.isEmpty else {
                finish(.failed("Rien entendu"), hideAfter: 1.5)
                return
            }
            TestHooks.log("dictée : \(result.text)")
            if TestHooks.noPaste {
                finish(.done("Collé"), hideAfter: 1.0)
            } else if Date().timeIntervalSince(stoppedAt) > 8 {
                // Après une longue attente (modèle en cours de téléchargement), le curseur n'est
                // sans doute plus au même endroit : on copie sans coller.
                Paster.copy(result.text)
                finish(.done("Copié · ⌘V pour coller"), hideAfter: 3)
            } else if settings.pasteAfterDictation {
                let pasted = Paster.paste(result.text, restoreClipboard: settings.restoreClipboard)
                finish(.done(pasted ? "Collé" : "Copié · ⌘V pour coller"), hideAfter: pasted ? 1.0 : 2.5)
                if !pasted, !askedForAccessibility {
                    // Sans l'autorisation Accessibilité, impossible de coller : on la demande une fois.
                    askedForAccessibility = true
                    Paster.requestTrust()
                }
            } else {
                Paster.copy(result.text)
                finish(.done("Copié"), hideAfter: 1.0)
            }

            let draft = Transcript(
                id: id, createdAt: date, mode: .dictation, duration: duration, engine: await engine.modelName,
                text: result.text, rawText: result.raw, app: app)
            let settings = self.settings
            let engine = self.engine
            // Le rangement ne doit pas retarder le collage.
            let saved: Transcript? = await Task.detached(priority: .utility) {
                var transcript = draft
                let store = settings.store
                if settings.keepAudio, let directory = try? store.ensureDirectory(forID: id) {
                    let name = "\(id)_mic.m4a"
                    if (try? AudioIO.writeM4A(samples, to: directory.appendingPathComponent(name))) != nil {
                        transcript.audioFiles = [name]
                    }
                }
                guard (try? store.save(transcript)) != nil else { return nil }
                if TestHooks.fakeMic == nil {
                    await VoiceprintStore.learn(from: samples, engine: engine)
                }
                return transcript
            }.value
            if let saved {
                lastTranscript = saved
                onLibraryChanged?()
            }
        } catch {
            // L'audio est mis de côté : il sera transcrit dès que le modèle sera disponible.
            let store = settings.store
            await Task.detached {
                if let url = try? Recovery.dictationURL(id: id, store: store) { Recovery.stash(samples, at: url) }
            }.value
            finish(.failed("Transcription impossible · audio conservé"), hideAfter: 3.5)
            Log.write("erreur : \(error.localizedDescription)")
        }
    }

    private func finishMeeting(
        id: String, date: Date, duration: Double, mic: ChannelRecorder, system: ChannelRecorder?
    ) async {
        let temporary = [mic.writer?.url, system?.writer?.url].compactMap { $0 }
        defer { activeSessions.remove(id) }
        do {
            try await engine.prepare(model: settings.model)
            modelStatus = .ready
            var channels = [ChannelAudio(channel: .mic, samples: mic.buffer.all(), offset: mic.offset)]
            if let system {
                channels.append(ChannelAudio(channel: .system, samples: system.buffer.all(), offset: system.offset))
            }
            let result = try await Pipeline.conversation(
                channels: channels, engine: engine, voiceprint: VoiceprintStore.load(), ownerOnMic: true
            ) { [weak self] stage in
                Task { @MainActor in
                    guard let self, case .processing = self.phase else { return }
                    let label: String
                    switch stage {
                    case .cleaningEcho: label = "Nettoyage de l'écho"
                    case .transcribing: label = "Transcription"
                    case .separatingSpeakers: label = "Séparation des voix"
                    }
                    self.setPhase(.processing(label))
                }
            }
            guard !result.segments.isEmpty else {
                temporary.forEach { try? FileManager.default.removeItem(at: $0) }
                finish(.failed("Rien entendu"), hideAfter: 1.5)
                return
            }

            let draft = Transcript(
                id: id, createdAt: date, mode: .meeting, duration: duration, engine: await engine.modelName,
                text: result.text, rawText: result.rawText, segments: result.segments, speakers: result.speakers)
            let settings = self.settings
            let recorded = channels
            let saved: Transcript? = await Task.detached(priority: .utility) {
                var transcript = draft
                let store = settings.store
                if settings.keepAudio, let directory = try? store.ensureDirectory(forID: id) {
                    for audio in recorded where !AudioLevel.isSilent(audio.samples) {
                        let name = "\(id)_\(audio.channel == .mic ? "mic" : "sys").m4a"
                        // Silence initial égal au décalage du canal : l'audio reste calé sur les horodatages.
                        let lead = [Float](repeating: 0, count: Int(audio.offset * Double(SpeechEngine.sampleRate)))
                        if (try? AudioIO.writeM4A(lead + audio.samples, to: directory.appendingPathComponent(name))) != nil {
                            transcript.audioFiles.append(name)
                        }
                    }
                }
                // Les WAV n'étaient qu'un filet de sécurité pendant l'enregistrement.
                temporary.forEach { try? FileManager.default.removeItem(at: $0) }
                return (try? store.save(transcript)) != nil ? transcript : nil
            }.value
            guard let saved else {
                finish(.failed("Enregistrement impossible"))
                return
            }
            lastTranscript = saved
            onLibraryChanged?()
            Sounds.play(.ready)
            finish(.done("Réunion enregistrée"), hideAfter: 6)
        } catch {
            // Les fichiers audio de la réunion restent en place pour une reprise ultérieure.
            finish(.failed("Transcription impossible · audio conservé"), hideAfter: 3.5)
            Log.write("erreur : \(error.localizedDescription)")
        }
    }

    // MARK: - États

    private func setPhase(_ phase: Phase) {
        TestHooks.log("état : \(phase)")
        self.phase = phase
        if phase != .idle { displayPhase = phase }
        if phase == .idle { scheduleUnload() } else { unloadTask?.cancel() }
        onPhaseChanged?(phase)
    }

    /// Après dix minutes sans enregistrement, on rend la mémoire des modèles.
    func scheduleUnload() {
        unloadTask?.cancel()
        let engine = self.engine
        unloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleUnloadDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .idle, !self.importing else { return }
            await engine.unload()
            TestHooks.log("modèles déchargés")
        }
    }

    /// Affiche un état final puis revient au repos.
    private func finish(_ phase: Phase, hideAfter delay: TimeInterval = 2.2) {
        setPhase(phase)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == phase else { return }
            self.setPhase(.idle)
        }
    }

    func dismiss() {
        switch phase {
        case .done, .failed:
            hideTask?.cancel()
            setPhase(.idle)
        default:
            break
        }
    }

    /// États factices pour le rendu hors écran des maquettes de l'interface.
    func debugSet(
        phase: Phase, mode: RecordingMode = .dictation, elapsed: TimeInterval = 0, levels: [Float]? = nil,
        committed: String = "", volatile: String = "", systemActive: Bool = false, transcript: Transcript? = nil
    ) {
        self.phase = phase
        displayPhase = phase
        self.mode = mode
        self.elapsed = elapsed
        if let levels { self.levels = levels }
        liveCommitted = committed
        liveVolatile = volatile
        self.systemActive = systemActive
        lastTranscript = transcript
        modelStatus = .ready
    }

    /// Transcrit un fichier audio choisi par l'utilisateur ou déposé dans le dossier iCloud.
    func importFile(
        _ url: URL, mode: RecordingMode = .imported, device: String = "mac", date: Date = Date()
    ) async -> Transcript? {
        imports += 1
        unloadTask?.cancel()
        defer {
            imports -= 1
            if phase == .idle { scheduleUnload() }
        }
        guard let transcript = try? await Importer.importAudio(at: url, mode: mode, device: device, date: date)
        else { return nil }
        lastTranscript = transcript
        onLibraryChanged?()
        return transcript
    }
}
