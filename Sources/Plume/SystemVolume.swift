import CoreAudio
import Foundation

/// Mutes the default output for the length of a dictation (music, a playing video), then
/// restores it. It uses the output's "mute" setting, not the volume: nothing has to be
/// remembered, and a sound the user muted themselves stays muted.
enum SystemVolume {
    private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// - Returns: `true` if the state changed (false if the output was already muted, or can't be muted).
    @discardableResult
    static func mute(_ on: Bool) -> Bool {
        guard let device = defaultOutput(), AudioObjectHasProperty(device, &address) else { return false }
        var current: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr else { return false }
        if on, current != 0 { return false }
        var value: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
