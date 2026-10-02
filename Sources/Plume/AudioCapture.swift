import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import PlumeKit

enum CaptureError: LocalizedError {
    case noInput
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInput: return "Aucun micro disponible."
        case .coreAudio(let step, let status): return "Capture du son système impossible (\(step), code \(status))."
        }
    }
}

/// Convertit en continu un flux audio quelconque vers du mono 16 kHz.
final class StreamResampler {
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(SpeechEngine.sampleRate), channels: 1, interleaved: false)!

    /// Tampon AVAudioEngine (micro).
    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0, let data = buffer.floatChannelData else { return [] }
        // Sur une carte son à plusieurs entrées, le micro n'occupe souvent qu'un canal : on ne
        // moyenne que les canaux qui portent du signal, pour ne pas diviser la voix par huit.
        let interleaved = buffer.format.isInterleaved
        func sample(_ channel: Int, _ frame: Int) -> Float {
            interleaved ? data[0][frame * channels + channel] : data[channel][frame]
        }
        var energy = [Float](repeating: 0, count: channels)
        for c in 0..<channels {
            var sum: Float = 0
            for f in 0..<frames {
                let value = sample(c, f)
                sum += value * value
            }
            energy[c] = sum
        }
        let loudest = energy.max() ?? 0
        let active = (0..<channels).filter { energy[$0] >= loudest * 0.05 }
        var mono = [Float](repeating: 0, count: frames)
        for c in active {
            for f in 0..<frames { mono[f] += sample(c, f) }
        }
        if active.count > 1 {
            let scale = 1 / Float(active.count)
            for f in 0..<frames { mono[f] *= scale }
        }
        return resample(mono, rate: buffer.format.sampleRate)
    }

    /// Tampons bruts Core Audio d'un micro, en flottants 32 bits : tous les flux d'entrée du
    /// périphérique, en ne gardant que les canaux qui portent du signal.
    func convert(microphone bufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> [Float] {
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        // Chaque canal : (pointeur, pas entre deux échantillons, nombre de trames).
        var channels: [(UnsafePointer<Float>, Int, Int)] = []
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count)
            let base = UnsafePointer(data.assumingMemoryBound(to: Float.self))
            for channel in 0..<count { channels.append((base + channel, count, frames)) }
        }
        guard let frames = channels.map(\.2).min(), frames > 0 else { return [] }
        // Sur une carte son à plusieurs entrées, le micro n'occupe souvent qu'un canal : on ne
        // moyenne que les canaux actifs, pour ne pas diviser la voix par huit.
        let energy = channels.map { channel -> Float in
            var sum: Float = 0
            for f in 0..<frames {
                let value = channel.0[f * channel.1]
                sum += value * value
            }
            return sum
        }
        let loudest = energy.max() ?? 0
        let active = channels.indices.filter { energy[$0] >= loudest * 0.05 }
        var mono = [Float](repeating: 0, count: frames)
        for index in active {
            let channel = channels[index]
            for f in 0..<frames { mono[f] += channel.0[f * channel.1] }
        }
        if active.count > 1 {
            let scale = 1 / Float(active.count)
            for f in 0..<frames { mono[f] *= scale }
        }
        return resample(mono, rate: format.mSampleRate)
    }

    /// Tampons bruts Core Audio (tap du son système), en flottants 32 bits.
    func convert(bufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> [Float] {
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        // Si la sortie audio possède aussi des entrées (carte son externe), leurs flux précèdent
        // celui du tap dans la liste : le son système est toujours à la fin.
        let separate = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let wanted = separate ? max(1, min(Int(format.mChannelsPerFrame), buffers.count)) : 1
        let tapBuffers = Array(buffers.suffix(wanted))
        guard let first = tapBuffers.first, first.mData != nil else { return [] }
        let interleavedChannels = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * interleavedChannels)
        guard frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)

        var used = 0
        for buffer in tapBuffers {
            guard let data = buffer.mData,
                Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * interleavedChannels) == frames
            else { continue }
            let source = data.assumingMemoryBound(to: Float.self)
            if interleavedChannels > 1 {
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<interleavedChannels { sum += source[f * interleavedChannels + c] }
                    mono[f] += sum / Float(interleavedChannels)
                }
            } else {
                for f in 0..<frames { mono[f] += source[f] }
            }
            used += 1
        }
        if used > 1 {
            let scale = 1 / Float(used)
            for f in 0..<frames { mono[f] *= scale }
        }
        return resample(mono, rate: format.mSampleRate)
    }

    private func resample(_ mono: [Float], rate: Double) -> [Float] {
        guard rate > 0 else { return [] }
        if rate == target.sampleRate { return mono }
        if converter == nil || sourceFormat?.sampleRate != rate {
            guard
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
            else { return [] }
            sourceFormat = format
            converter = AVAudioConverter(from: format, to: target)
        }
        guard let converter, let sourceFormat,
            let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(mono.count))
        else { return [] }
        input.frameLength = AVAudioFrameCount(mono.count)
        mono.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: mono.count) }

        let capacity = AVAudioFrameCount(Double(mono.count) * target.sampleRate / rate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}

/// Capture du micro choisi dans les réglages (par défaut, celui du Mac).
///
/// On lit directement le périphérique par Core Audio plutôt que par AVAudioEngine : celui-ci
/// suit l'entrée par défaut du système — que des écouteurs ou une enceinte Bluetooth
/// détournent dès qu'ils se connectent — et ne livre plus rien si on lui en impose une autre.
final class MicCapture {
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var aliveListener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "plume.microphone", qos: .userInitiated)
    private let control = DispatchQueue(label: "plume.microphone.control")
    private let resampler = StreamResampler()
    private var running = false
    var onSamples: (([Float]) -> Void)?
    /// Le micro a disparu et aucun autre n'a pu prendre le relais.
    var onFailure: (() -> Void)?
    /// Nom du micro effectivement utilisé (pour le journal et le diagnostic).
    private(set) var deviceName = "aucun"

    private static var aliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() throws {
        try open()
        running = true
    }

    private func open() throws {
        // Le micro choisi s'il est branché, sinon celui du Mac, sinon l'entrée du système.
        var device = AudioObjectID(kAudioObjectUnknown)
        if let preferred = AudioDevices.preferredInput() {
            device = preferred.deviceID
            deviceName = preferred.name
        } else {
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            deviceName = "entrée par défaut du système"
        }
        guard device != kAudioObjectUnknown else { throw CaptureError.noInput }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format)
        guard status == noErr, format.mSampleRate > 0 else { throw CaptureError.coreAudio("format du micro", status) }
        TestHooks.log("micro : \(deviceName), \(Int(format.mSampleRate)) Hz, \(format.mChannelsPerFrame) canal(aux)")

        let streamFormat = format
        var described = false
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            if !described {
                described = true
                let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                TestHooks.log(
                    "micro : premier tampon [\(list.map { "\($0.mNumberChannels) canal(aux) × \($0.mDataByteSize) octets" }.joined(separator: ", "))], "
                        + "drapeaux \(streamFormat.mFormatFlags), \(streamFormat.mBitsPerChannel) bits")
            }
            let samples = self.resampler.convert(microphone: input, format: streamFormat)
            if !samples.isEmpty { self.onSamples?(samples) }
        }
        guard status == noErr, let procID else { throw CaptureError.coreAudio("lecture du micro", status) }
        status = AudioDeviceStart(device, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(device, procID)
            self.procID = nil
            throw CaptureError.coreAudio("démarrage du micro", status)
        }
        deviceID = device

        // Micro débranché ou éteint en cours d'enregistrement : on bascule sur un autre.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceVanished() }
        aliveListener = listener
        AudioObjectAddPropertyListenerBlock(device, &Self.aliveAddress, control, listener)
    }

    private func close() {
        guard deviceID != kAudioObjectUnknown else { return }
        if let aliveListener {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.aliveAddress, control, aliveListener)
            self.aliveListener = nil
        }
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func deviceVanished() {
        DispatchQueue.main.async { [self] in
            guard running else { return }
            Log.write("micro : « \(deviceName) » a disparu, bascule sur un autre micro")
            close()
            do {
                try open()
            } catch {
                Log.write("micro : aucun micro de remplacement (\(error.localizedDescription))")
                onFailure?()
            }
        }
    }

    func stop() {
        running = false
        close()
    }
}

/// Capture de tout le son émis par l'ordinateur (voix des autres participants d'une visio,
/// même au casque), via un « process tap » Core Audio. Ne demande que l'autorisation
/// « Enregistrement audio du système », pas l'enregistrement de l'écran.
final class SystemAudioCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private let queue = DispatchQueue(label: "plume.system-audio", qos: .userInitiated)
    private let resampler = StreamResampler()
    var onSamples: (([Float]) -> Void)?
    private var outputListener: AudioObjectPropertyListenerBlock?
    /// Faux après `stop()` : un écouteur ou une minuterie encore en vol ne relance rien.
    private var active = false
    private var formatWatch: DispatchSourceTimer?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// File dédiée aux appels Core Audio de mise en place. La première fois, macOS suspend
    /// la création du tap tant que l'utilisateur n'a pas répondu à la demande d'autorisation :
    /// rien de tout cela ne doit s'exécuter sur le thread principal.
    private let control = DispatchQueue(label: "plume.system-audio.control")

    /// Démarre la capture en arrière-plan. Les échantillons arrivent dès que le tap est prêt
    /// (immédiatement, ou après l'accord de l'utilisateur la première fois).
    func start() throws {
        control.async { [self] in
            active = true
            do {
                try startTap()
            } catch {
                Log.write("son système : \(error.localizedDescription)")
                return
            }
            // Casque branché ou débranché en pleine réunion : on recrée le tap sur la nouvelle sortie.
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.active else { return }
                self.stopTap()
                try? self.startTap()
            }
            outputListener = listener
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, control, listener)

            // La sortie peut changer de fréquence sans changer de périphérique (casque Bluetooth
            // qui passe en mode appel) : on relit le format et on recrée le tap s'il a bougé.
            let timer = DispatchSource.makeTimerSource(queue: control)
            timer.schedule(deadline: .now() + 3, repeating: 3)
            timer.setEventHandler { [weak self] in
                guard let self, self.active, self.tapID != kAudioObjectUnknown else { return }
                var current = AudioStreamBasicDescription()
                var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                guard AudioObjectGetPropertyData(self.tapID, &address, 0, nil, &size, &current) == noErr,
                    current.mSampleRate != self.format.mSampleRate
                        || current.mChannelsPerFrame != self.format.mChannelsPerFrame
                else { return }
                Log.write("son système : format modifié, tap recréé")
                self.stopTap()
                try? self.startTap()
            }
            timer.resume()
            formatWatch = timer
        }
    }

    func stop() {
        control.async { [self] in
            active = false
            formatWatch?.cancel()
            formatWatch = nil
            if let outputListener {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, control, outputListener)
                self.outputListener = nil
            }
            stopTap()
        }
    }

    private func startTap() throws {
        // Tap global stéréo ; on s'exclut soi-même pour ne pas capter nos propres sons.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObjects())
        description.uuid = UUID()
        description.name = "Plume"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "création du tap")
        tapID = tap

        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "format du tap")

        // Le tap se lit à travers un périphérique agrégé privé, calé sur la sortie réelle.
        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Plume (son système)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "périphérique agrégé")
        aggregateID = device

        let tapFormat = format
        Log.write(
            "son système : tap créé (\(Int(tapFormat.mSampleRate)) Hz, \(tapFormat.mChannelsPerFrame) canaux, "
                + "\(tapFormat.mBitsPerChannel) bits, drapeaux \(tapFormat.mFormatFlags))")
        var described = false
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
                guard let self else { return }
                if !described {
                    described = true
                    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                    let layout = list.map { "\($0.mNumberChannels) canal(aux) × \($0.mDataByteSize) octets" }
                    Log.write("son système : premier tampon reçu [\(layout.joined(separator: ", "))]")
                }
                let samples = self.resampler.convert(bufferList: input, format: tapFormat)
                if !samples.isEmpty { self.onSamples?(samples) }
            }, "lecture du tap")
        try check(AudioDeviceStart(aggregateID, procID), "démarrage")
    }

    private func stopTap() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            procID = nil
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            stopTap()
            throw CaptureError.coreAudio(step, status)
        }
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw CaptureError.coreAudio("sortie par défaut", status) }

        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw CaptureError.coreAudio("identifiant de la sortie", status) }
        return uid as String
    }

    /// Objet Core Audio de notre propre processus, s'il existe déjà.
    private static func ownProcessObjects() -> [AudioObjectID] {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { return [] }
        return [object]
    }
}

/// Un canal en cours d'enregistrement : tampon en mémoire, fichier de secours, niveau sonore.
final class ChannelRecorder: @unchecked Sendable {
    let channel: AudioChannel
    let buffer = SampleBuffer()
    var onLevel: ((Float) -> Void)?
    private(set) var writer: WavWriter?
    private let sessionStart: Date
    private let lock = NSLock()
    private var firstSampleOffset: Double?

    init(channel: AudioChannel, sessionStart: Date) {
        self.channel = channel
        self.sessionStart = sessionStart
    }

    /// Décalage du premier échantillon par rapport au début de la session.
    var offset: Double {
        lock.lock()
        defer { lock.unlock() }
        return firstSampleOffset ?? 0
    }

    /// Branche le fichier de secours, en y versant d'abord tout ce qui a déjà été capté.
    func attach(_ writer: WavWriter) {
        lock.lock()
        defer { lock.unlock() }
        let captured = buffer.all()
        if !captured.isEmpty { writer.append(captured) }
        self.writer = writer
    }

    func append(_ samples: [Float]) {
        let rate = Double(SpeechEngine.sampleRate)
        let now = Date().timeIntervalSince(sessionStart)
        lock.lock()
        if firstSampleOffset == nil {
            firstSampleOffset = max(0, now - Double(samples.count) / rate)
        }
        let start = firstSampleOffset ?? 0

        // Si la capture s'est interrompue (changement de périphérique), on comble par du
        // silence pour que les horodatages restent alignés entre les canaux.
        let expected = Int((now - start) * rate)
        let missing = expected - (buffer.count + samples.count)
        if missing > Int(rate / 2) {
            // Au plus trente secondes de silence : après une longue interruption (veille de
            // l'ordinateur), on décale l'origine plutôt que de fabriquer des heures de zéros.
            let padded = min(missing, Int(rate) * 30)
            if padded < missing {
                firstSampleOffset = start + Double(missing - padded) / rate
            }
            let silence = [Float](repeating: 0, count: padded)
            buffer.append(silence)
            writer?.append(silence)
        }
        buffer.append(samples)
        writer?.append(samples)
        lock.unlock()
        onLevel?(AudioLevel.rms(samples[...]))
    }
}
