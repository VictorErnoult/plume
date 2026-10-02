import AVFoundation
import AppKit
import PlumeKit

/// Les sons de Plume, synthétisés à la volée. C'est le kit « Bois » du portfolio soyakil.fr,
/// porté tel quel : un marimba très sobre (partiels 1 : 3,9 : 9,2), gamme pentatonique,
/// survols en sinusoïde pure, et des « gonflements » à attaque lente qui glissent d'une octave.
/// Les sons d'enregistrement reprennent cette recette, plus graves et plus feutrés ; un pack de
/// sons enregistrés (`Resources/Sounds`), choisi dans les réglages, peut les remplacer.
enum Sounds {
    enum Kind: Hashable {
        // Enregistrement.
        case start, stop, cancel, meetingOn, meetingOff, ready
        // Fenêtre.
        case windowOpen
        case page(Int)
        case click, confirm, refuse
        case toggleOn, toggleOff, tab
        case sliderStep(Int)
        // Survols : à jouer avec `hover`, jamais avec `play`.
        case hoverNav, hoverRow, hoverCard, hoverButton
    }

    /// Faux tant que l'app n'est pas lancée pour de bon : la ligne de commande et les rendus
    /// hors écran restent muets.
    @MainActor static var live = false

    // MARK: Jouer

    @MainActor
    static func play(_ kind: Kind) {
        let settings = PlumeSettings.shared
        TestHooks.log("son : \(kind)")
        // Les essais avec micro simulé restent silencieux.
        guard live, settings.sounds, settings.soundVolume > 0.01, TestHooks.fakeMic == nil else { return }
        // Le réglage par défaut (0,7) donne le niveau du portfolio.
        let level = min(1.45, settings.soundVolume / 0.7)
        let pack = SoundPack(rawValue: settings.soundPack) ?? .standard
        queue.async { output(kind, pack: pack, level: level) }
    }

    private static var lastHover: CFTimeInterval = 0
    private static var lastPointer = NSPoint(x: -1, y: -1)

    /// Son de survol. Il ne part que si le pointeur a réellement bougé : une liste qui défile
    /// sous une souris immobile ne doit pas chanter. Pas plus d'un son toutes les 60 ms.
    @MainActor
    static func hover(_ kind: Kind) {
        let pointer = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        guard pointer != lastPointer, now - lastHover >= 0.06 else { return }
        lastPointer = pointer
        lastHover = now
        play(kind)
    }

    // MARK: Les voix

    private struct Voice {
        enum Shape { case tick, swell, dyad }
        /// Degré dans la gamme pentatonique (0 = la 440 Hz).
        var deg: Int
        var dur: Double
        var gain: Double
        var shape: Shape = .tick
        /// Fondamentale seule, avec un souffle de 5 ms : le timbre des survols.
        var pure = false
        /// Rapport de la fréquence de départ d'un gonflement (0,5 : monte d'une octave).
        var glide = 0.5
        /// Intervalle, en degrés, de la seconde note d'une dyade.
        var interval = 0
        /// Coupe-haut final, en Hz : plus bas, le son est plus feutré.
        var cutoff = 6200.0
        /// Part de réflexions courtes, réparties à gauche et à droite, qui donnent de l'espace.
        var space = 0.0
    }

    private static func recipe(for kind: Kind) -> Voice {
        switch kind {
        // Enregistrement : la recette de l'ouverture de page, une octave plus haut pour rester
        // audible sur les haut-parleurs du Mac, coupe-haut bas, un peu d'espace.
        case .start: return Voice(deg: -5, dur: 0.50, gain: 0.78, shape: .swell, cutoff: 2600, space: 0.5)
        case .stop: return Voice(deg: -5, dur: 0.50, gain: 0.68, shape: .swell, glide: 2, cutoff: 2600, space: 0.5)
        case .cancel: return Voice(deg: -4, dur: 0.20, gain: 0.30, shape: .dyad, interval: -2, cutoff: 3200, space: 0.35)
        case .meetingOn: return Voice(deg: -5, dur: 0.20, gain: 0.32, shape: .dyad, interval: 3, cutoff: 3200, space: 0.35)
        case .meetingOff: return Voice(deg: -5, dur: 0.12, gain: 0.24, cutoff: 3200, space: 0.35)
        case .ready: return Voice(deg: -4, dur: 0.20, gain: 0.30, shape: .dyad, interval: 3, cutoff: 3200, space: 0.35)
        // Fenêtre : les voix du portfolio, à l'identique.
        case .windowOpen: return Voice(deg: -5, dur: 0.24, gain: 0.21, shape: .swell)
        case .page(let tint): return Voice(deg: -10 + tint, dur: 0.52, gain: 0.34, shape: .swell)
        case .click, .confirm: return Voice(deg: 3, dur: 0.18, gain: 0.26, shape: .dyad, interval: 3)
        case .refuse: return Voice(deg: 1, dur: 0.20, gain: 0.24, shape: .dyad, interval: -2)
        case .toggleOn: return Voice(deg: 1, dur: 0.07, gain: 0.11, pure: true)
        case .toggleOff: return Voice(deg: -1, dur: 0.05, gain: 0.10, pure: true)
        case .tab, .hoverNav: return Voice(deg: 5, dur: 0.04, gain: 0.105, pure: true)
        case .sliderStep(let step): return Voice(deg: step, dur: 0.028, gain: 0.055, pure: true)
        case .hoverRow: return Voice(deg: 4, dur: 0.05, gain: 0.11, pure: true)
        case .hoverCard: return Voice(deg: 2, dur: 0.07, gain: 0.13, pure: true)
        case .hoverButton: return Voice(deg: 6, dur: 0.04, gain: 0.10, pure: true)
        }
    }

    private static let scale = [0, 2, 4, 7, 9]

    private static func pitch(_ degree: Int) -> Double {
        let octave = Int((Double(degree) / 5).rounded(.down))
        let step = ((degree % 5) + 5) % 5
        return 440 * pow(2, Double(octave * 12 + scale[step]) / 12)
    }

    // MARK: Synthèse

    private static let sampleRate = 48_000.0
    /// Niveau général du kit.
    private static let master = 0.55

    /// Un son en cours de fabrication : on y dépose des sinusoïdes et des souffles.
    private struct Canvas {
        var samples: [Double]

        init(seconds: Double) {
            samples = [Double](repeating: 0, count: Int(seconds * Sounds.sampleRate) + 1)
        }

        /// Enveloppe exponentielle : montée jusqu'à `peak` en `attack`, puis extinction.
        private func envelope(_ t: Double, dur: Double, peak: Double, attack: Double) -> Double {
            let floor = 1e-4
            let top = max(peak, 2e-4)
            if t < attack { return floor * pow(top / floor, t / attack) }
            if t < dur { return top * pow(floor / top, (t - attack) / max(dur - attack, 1e-4)) }
            return 0
        }

        mutating func tone(at start: Double, frequency: Double, dur: Double, peak: Double, attack: Double, glide: Double?) {
            guard frequency > 15, frequency < 15_000 else { return }
            let first = Int(start * Sounds.sampleRate)
            let count = Int(dur * Sounds.sampleRate)
            var phase = 0.0
            for i in 0..<count where first + i < samples.count {
                let t = Double(i) / Sounds.sampleRate
                var f = frequency
                if let glide {
                    let travel = min(1, t / (dur * 0.75))
                    f = frequency * glide * pow(1 / glide, travel)
                }
                phase += 2 * Double.pi * f / Sounds.sampleRate
                samples[first + i] += sin(phase) * envelope(t, dur: dur, peak: peak, attack: attack)
            }
        }

        /// Souffle : bruit blanc passé dans un filtre passe-bande.
        mutating func breath(at start: Double, dur: Double, peak: Double, attack: Double, band: Double) {
            let first = Int(start * Sounds.sampleRate)
            let count = Int(dur * Sounds.sampleRate)
            var filter = Biquad.bandpass(frequency: min(band, 16_000), q: 1.4)
            for i in 0..<count where first + i < samples.count {
                let t = Double(i) / Sounds.sampleRate
                samples[first + i] += filter.process(Double.random(in: -1...1)) * envelope(t, dur: dur, peak: peak, attack: attack)
            }
        }

        /// Une note du kit : bois complet, ou fondamentale seule.
        mutating func note(at start: Double, frequency: Double, dur: Double, level: Double, voice: Voice, soft: Bool) {
            let glide: Double? = soft ? voice.glide : nil
            let attack = soft ? dur * 0.25 : 0.002
            if voice.pure {
                tone(at: start, frequency: frequency, dur: dur, peak: level * 0.62, attack: attack, glide: glide)
                breath(at: start, dur: 0.005, peak: level * 0.1, attack: 0.001, band: frequency * 2.4)
                return
            }
            tone(at: start, frequency: frequency, dur: dur, peak: level * 0.6, attack: attack, glide: glide)
            tone(
                at: start, frequency: frequency * 3.9, dur: dur * 0.3, peak: level * 0.15, attack: soft ? dur * 0.25 : 0.001,
                glide: glide)
            tone(at: start, frequency: frequency * 9.2, dur: dur * 0.16, peak: level * 0.05, attack: 0.001, glide: glide)
            breath(
                at: start, dur: soft ? dur * 0.6 : 0.007, peak: level * (soft ? 0.12 : 0.28), attack: soft ? dur * 0.25 : 0.001,
                band: frequency * 2.4)
        }
    }

    private struct Biquad {
        var b0, b1, b2, a1, a2: Double
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        static func bandpass(frequency: Double, q: Double) -> Biquad {
            let w = 2 * Double.pi * frequency / Sounds.sampleRate
            let alpha = sin(w) / (2 * q)
            let a0 = 1 + alpha
            return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
        }

        static func lowpass(frequency: Double, resonance: Double) -> Biquad {
            let w = 2 * Double.pi * frequency / Sounds.sampleRate
            let alpha = sin(w) / (2 * pow(10, resonance / 20))
            let a0 = 1 + alpha
            let c = cos(w)
            return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
        }

        static func highpass(frequency: Double, resonance: Double) -> Biquad {
            let w = 2 * Double.pi * frequency / Sounds.sampleRate
            let alpha = sin(w) / (2 * pow(10, resonance / 20))
            let a0 = 1 + alpha
            let c = cos(w)
            return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }

    /// Réflexions courtes (retard en secondes, niveau, côté), pour envelopper sans réverbérer.
    private static let reflections: [(delay: Double, level: Double, left: Bool)] = [
        (0.011, 0.20, true), (0.017, 0.17, false), (0.023, 0.13, true), (0.031, 0.10, false), (0.043, 0.07, true),
        (0.059, 0.05, false),
    ]

    /// Fabrique un son : deux canaux, à `sampleRate`. `exact` retire les petites variations
    /// de hauteur et de niveau qui évitent, à l'usage, l'effet de répétition mécanique.
    private static func render(_ kind: Kind, level: Double = 1, exact: Bool = false) -> (left: [Float], right: [Float]) {
        let voice = recipe(for: kind)
        let detune = exact ? 1 : pow(2, Double.random(in: -1...1) * 12 / 1200)
        let gain = voice.gain * 1.05 * (exact ? 1 : 1 + Double.random(in: -1...1) * 0.06) * master * level
        let dur = voice.dur * 1.15
        let frequency = pitch(voice.deg) * detune

        var canvas = Canvas(seconds: (voice.shape == .dyad ? dur * 1.3 : dur) + 0.02)
        switch voice.shape {
        case .swell:
            canvas.note(at: 0, frequency: frequency, dur: dur, level: 1, voice: voice, soft: true)
        case .dyad:
            let second = pitch(voice.deg + voice.interval) * detune
            canvas.note(at: 0, frequency: frequency, dur: dur * 0.5, level: 0.85, voice: voice, soft: false)
            canvas.note(at: dur * 0.3, frequency: second, dur: dur, level: 0.7, voice: voice, soft: false)
        case .tick:
            canvas.note(at: 0, frequency: frequency, dur: dur, level: 1, voice: voice, soft: false)
        }

        var filter = Biquad.lowpass(frequency: voice.cutoff, resonance: 0.7)
        let dry = canvas.samples.map { filter.process($0) * gain }

        let tail = voice.space > 0 ? Int(0.07 * sampleRate) : 0
        var left = [Double](repeating: 0, count: dry.count + tail)
        var right = left
        for (i, sample) in dry.enumerated() {
            left[i] = sample
            right[i] = sample
        }
        if voice.space > 0 {
            for reflection in reflections {
                let offset = Int(reflection.delay * sampleRate)
                let amount = reflection.level * voice.space
                for (i, sample) in dry.enumerated() {
                    if reflection.left { left[i + offset] += sample * amount } else { right[i + offset] += sample * amount }
                }
            }
        }
        // Dernières millisecondes ramenées à zéro : pas de claquement en fin de son.
        let fade = min(left.count, Int(0.004 * sampleRate))
        for i in 0..<fade {
            let k = Double(i) / Double(fade)
            left[left.count - 1 - i] *= k
            right[right.count - 1 - i] *= k
        }
        return (left.map { Float(max(-1, min(1, $0))) }, right.map { Float(max(-1, min(1, $0))) })
    }

    // MARK: Sons enregistrés

    /// Un son enregistré qui remplace la synthèse, allégé pour rester discret.
    struct Sample {
        /// Fichier de `Resources/Sounds`, sans l'extension.
        var name: String
        /// Début du passage gardé dans le fichier, en secondes.
        var offset = 0.0
        /// Gain qui l'accorde au niveau du kit.
        var gain: Double
        /// Durée gardée, en secondes : la queue est coupée, avec un fondu sur la fin.
        var length: Double
        /// Coupe-bas, en Hz : retire le corps grave pour un son moins large.
        var lowCut: Double
        /// Coupe-haut, en Hz : adoucit les aigus.
        var highCut = 16_000.0
        /// Transposition, en demi-tons (négatif : plus grave, et un peu plus lent).
        var semitones = 0.0
    }

    /// Fichiers déjà décodés, par nom (sur la file des sons ou à l'export seulement).
    private static var decoded: [String: (left: [Float], right: [Float])] = [:]

    /// Le son enregistré de `kind`, au niveau voulu, ou nil s'il n'y en a pas : la synthèse prend
    /// alors le relais.
    private static func recorded(_ kind: Kind, pack: SoundPack, level: Double = 1) -> (left: [Float], right: [Float])? {
        guard let sample = pack.sample(for: kind), let audio = decode(sample.name) else { return nil }
        let first = min(audio.left.count, Int(sample.offset * sampleRate))
        // Transposer, c'est relire le fichier plus lentement : `rate` échantillons source par
        // échantillon produit.
        let rate = pow(2, sample.semitones / 12)
        let count = min(Int(Double(audio.left.count - first - 1) / rate), Int(sample.length * sampleRate))
        // Fondu sur les 40 % finaux de la durée gardée.
        let fadeStart = Int(Double(count) * 0.6)
        func shape(_ channel: [Float]) -> [Float] {
            var low = Biquad.highpass(frequency: sample.lowCut, resonance: 0.7)
            var high = Biquad.lowpass(frequency: sample.highCut, resonance: 0.7)
            return (0..<max(count, 0)).map { i in
                let position = Double(i) * rate
                let index = first + Int(position)
                let fraction = position - position.rounded(.down)
                let source = Double(channel[index]) * (1 - fraction) + Double(channel[index + 1]) * fraction
                var value = high.process(low.process(source)) * sample.gain * level
                if i >= fadeStart {
                    let k = 1 - Double(i - fadeStart) / Double(max(count - fadeStart, 1))
                    value *= k * k
                }
                return Float(max(-1, min(1, value)))
            }
        }
        return (shape(audio.left), shape(audio.right))
    }

    private static func decode(_ name: String) -> (left: [Float], right: [Float])? {
        if let cached = decoded[name] { return cached }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true)
        // Binaire lancé hors de l'app (développement) : les sons sont dans le dépôt.
        let development = Bundle.repositoryResource("Sounds")
        let url = [bundled, development].compactMap { $0?.appendingPathComponent("\(name).mp3") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url, let file = try? AVAudioFile(forReading: url) else { return nil }
        let source = file.processingFormat
        guard source.sampleRate == sampleRate, source.channelCount <= 2,
            let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buffer)) != nil, let channels = buffer.floatChannelData
        else {
            Log.write("sons : \(name).mp3 illisible, son synthétisé à la place")
            return nil
        }
        let count = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: channels[0], count: count))
        let right = source.channelCount == 2 ? Array(UnsafeBufferPointer(start: channels[1], count: count)) : left
        decoded[name] = (left, right)
        return (left, right)
    }

    // MARK: Sortie

    private static let queue = DispatchQueue(label: "plume.sounds", qos: .userInteractive)
    private static let engine = AVAudioEngine()
    private static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    private static var players: [AVAudioPlayerNode] = []
    private static var nextPlayer = 0
    private static var release: DispatchWorkItem?

    /// Sur la file des sons : fabrique le son et le confie à un lecteur libre.
    private static func output(_ kind: Kind, pack: SoundPack, level: Double) {
        let (left, right) = recorded(kind, pack: pack, level: level) ?? render(kind, level: level)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
            let channels = buffer.floatChannelData
        else { return }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: left.count) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: right.count) }

        if players.isEmpty {
            for _ in 0..<8 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log.write("sons : sortie audio indisponible — \(error.localizedDescription)")
                return
            }
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }

        // On rend la sortie audio au système quand plus rien ne sonne.
        release?.cancel()
        let work = DispatchWorkItem {
            players.forEach { $0.stop() }
            engine.stop()
        }
        release = work
        queue.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: Contrôle

    /// Écrit les sons dans un dossier, pour les écouter ou les contrôler (`plume sounds <dossier>`) :
    /// le kit complet, puis un sous-dossier par pack avec ses sons d'enregistrement.
    static func export(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let kinds: [(String, Kind)] = [
            ("debut", .start), ("fin", .stop), ("annulation", .cancel), ("reunion-on", .meetingOn),
            ("reunion-off", .meetingOff), ("pret", .ready), ("fenetre", .windowOpen), ("page-0", .page(0)),
            ("page-3", .page(3)), ("clic", .click), ("refus", .refuse), ("interrupteur-on", .toggleOn),
            ("interrupteur-off", .toggleOff), ("onglet", .tab), ("cran", .sliderStep(0)), ("survol-ligne", .hoverRow),
            ("survol-carte", .hoverCard), ("survol-bouton", .hoverButton),
        ]
        for (name, kind) in kinds {
            let (left, right) = render(kind, exact: true)
            try? wav(left: left, right: right).write(to: directory.appendingPathComponent("\(name).wav"))
        }
        for pack in SoundPack.allCases {
            let folder = directory.appendingPathComponent(pack.rawValue, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, kind) in kinds.prefix(6) {
                guard let audio = recorded(kind, pack: pack) else { continue }
                try? wav(left: audio.left, right: audio.right).write(to: folder.appendingPathComponent("\(name).wav"))
            }
        }
    }

    private static func wav(left: [Float], right: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(left.count * 4)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(2))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 4)
        append(UInt16(4))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        for i in 0..<left.count {
            append(Int16(left[i] * 32_767))
            append(Int16(right[i] * 32_767))
        }
        return data
    }
}

/// Les packs de sons d'enregistrement, au choix dans les réglages. Un pack remplace tout ou partie
/// des sons d'enregistrement ; les autres restent synthétisés.
enum SoundPack: String, CaseIterable, Identifiable {
    case pluck, bips, clics, melodie, glisse, bois

    static let standard = SoundPack.pluck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pluck: return "Pluck"
        case .bips: return "Bips"
        case .clics: return "Clics"
        case .melodie: return "Mélodie"
        case .glisse: return "Glisse"
        case .bois: return "Bois (synthétisé)"
        }
    }

    typealias Sample = Sounds.Sample

    func sample(for kind: Sounds.Kind) -> Sample? {
        switch (self, kind) {
        // Cinq notes pincées, avec réverbération, à 0 ; 2,4 ; 4,4 ; 6,5 et 8,6 s : la plus haute
        // ouvre, la plus basse ferme.
        case (.pluck, .start): return Sample(name: "pluck", offset: 6.52, gain: 0.25, length: 0.5, lowCut: 120)
        case (.pluck, .stop): return Sample(name: "pluck", offset: 0.02, gain: 0.25, length: 0.5, lowCut: 120)
        case (.pluck, .cancel): return Sample(name: "pluck", offset: 8.57, gain: 0.22, length: 0.4, lowCut: 120)
        case (.pluck, .meetingOn): return Sample(name: "pluck", offset: 2.38, gain: 0.22, length: 0.4, lowCut: 120)
        case (.pluck, .ready): return Sample(name: "pluck", offset: 4.43, gain: 0.25, length: 0.5, lowCut: 120)
        // Deux bips : l'un monte (au début), l'autre descend (vers 1,5 s).
        case (.bips, .start): return Sample(name: "bip", gain: 0.35, length: 0.26, lowCut: 150, highCut: 3500, semitones: -3)
        case (.bips, .stop):
            return Sample(name: "bip", offset: 1.5, gain: 0.35, length: 0.26, lowCut: 150, highCut: 3500, semitones: -3)
        // Deux clics : « on » au début, « off » vers 1,07 s.
        case (.clics, .start): return Sample(name: "clic", gain: 0.35, length: 0.08, lowCut: 120)
        case (.clics, .stop): return Sample(name: "clic", offset: 1.07, gain: 0.35, length: 0.08, lowCut: 120)
        case (.melodie, .start): return Sample(name: "melodie-debut", gain: 0.45, length: 0.32, lowCut: 500)
        case (.melodie, .stop): return Sample(name: "melodie-fin", gain: 1.0, length: 0.50, lowCut: 500)
        case (.glisse, .start): return Sample(name: "glisse-debut", gain: 0.5, length: 0.3, lowCut: 200)
        case (.glisse, .stop): return Sample(name: "glisse-fin", offset: 0.03, gain: 0.45, length: 0.32, lowCut: 200)
        default: return nil
        }
    }
}
