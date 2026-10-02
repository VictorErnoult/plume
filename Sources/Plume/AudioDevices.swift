import CoreAudio
import Foundation
import PlumeKit

/// Un micro disponible sur le Mac.
struct InputDevice: Identifiable, Equatable {
    var deviceID: AudioDeviceID
    /// Identifiant stable d'un branchement à l'autre.
    var uid: String
    var name: String
    var isBuiltIn: Bool
    var isBluetooth: Bool

    var id: String { uid }
}

/// Liste des micros et choix de celui que Plume utilise.
///
/// Plume ne suit pas l'entrée par défaut du système : brancher des écouteurs Bluetooth ne doit
/// pas déplacer la dictée sur leur micro. Sauf choix explicite dans les réglages, c'est le
/// micro intégré du Mac qui est utilisé.
enum AudioDevices {
    static func inputs() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannels(of: id) > 0, let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                let name = string(kAudioObjectPropertyName, of: id)
            else { return nil }
            let transport = transportType(of: id)
            // Les périphériques agrégés servent à la capture du son système, pas à la voix.
            guard transport != kAudioDeviceTransportTypeAggregate else { return nil }
            return InputDevice(
                deviceID: id, uid: uid, name: name, isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
                isBluetooth: transport == kAudioDeviceTransportTypeBluetooth
                    || transport == kAudioDeviceTransportTypeBluetoothLE)
        }
    }

    /// Le micro à utiliser : celui choisi dans les réglages s'il est branché, sinon le micro
    /// intégré, sinon `nil` (entrée par défaut du système).
    static func preferredInput(among devices: [InputDevice] = inputs()) -> InputDevice? {
        if let uid = PlumeSettings.shared.microphoneUID, let chosen = devices.first(where: { $0.uid == uid }) {
            return chosen
        }
        return devices.first(where: \.isBuiltIn)
    }

    private static func inputChannels(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value as String : nil
    }
}
