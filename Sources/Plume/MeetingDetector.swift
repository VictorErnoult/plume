import CoreAudio
import Foundation

/// Detects the start of a call: a video call app (Zoom, Teams, Meet in the browser…) that
/// starts using the microphone. Plume then offers to record the meeting, and also notices
/// the end of the call. Nothing is listened to here: it only reads the list of audio processes,
/// which Core Audio keeps up to date.
@MainActor
final class MeetingDetector {
    /// Call detected: readable name of the app.
    var onCallStarted: ((String) -> Void)?
    /// The app that held the microphone let it go.
    var onCallEnded: (() -> Void)?

    private var timer: Timer?
    /// Since when each process has held the microphone.
    private var since: [pid_t: Date] = [:]
    /// Processes we already made an offer for, until they release the microphone.
    private var announced = Set<pid_t>()
    private var fakeStart: Date?

    /// Video call apps and browsers (Meet, Teams web…). A browser also opens the microphone for
    /// many other things: we ask more persistence from it before offering.
    nonisolated static let apps: [String: (name: String, delay: TimeInterval)] = [
        "us.zoom.xos": ("Zoom", 3),
        "zoom.us": ("Zoom", 3),
        "com.microsoft.teams2": ("Teams", 3),
        "com.microsoft.teams": ("Teams", 3),
        "com.apple.FaceTime": ("FaceTime", 3),
        "com.cisco.webexmeetingsapp": ("Webex", 3),
        "com.webex.meetingmanager": ("Webex", 3),
        "com.tinyspeck.slackmacgap": ("Slack", 4),
        "com.hnc.Discord": ("Discord", 4),
        "com.skype.skype": ("Skype", 3),
        "net.whatsapp.WhatsApp": ("WhatsApp", 4),
        "com.google.Chrome": ("Chrome", 8),
        "com.google.Chrome.canary": ("Chrome", 8),
        "com.apple.Safari": ("Safari", 8),
        "company.thebrowser.Browser": ("Arc", 8),
        "org.mozilla.firefox": ("Firefox", 8),
        "com.microsoft.edgemac": ("Edge", 8),
        "com.brave.Browser": ("Brave", 8),
        "com.vivaldi.Vivaldi": ("Vivaldi", 8),
        "com.operasoftware.Opera": ("Opera", 8),
        "com.kagi.kagimacOS": ("Orion", 8),
        "ai.perplexity.comet": ("Comet", 8),
        "com.openai.atlas": ("Atlas", 8),
    ]

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let now = Date()
        var active: [(pid: pid_t, name: String, delay: TimeInterval)] = []
        for process in Self.processesUsingInput() {
            guard let app = Self.apps[process.bundleID] else { continue }
            active.append((process.pid, app.name, app.delay))
        }
        // PLUME_FAKE_CALL=zoom.us: an imaginary call, five seconds after launch.
        if let fake = ProcessInfo.processInfo.environment["PLUME_FAKE_CALL"], let app = Self.apps[fake] {
            fakeStart = fakeStart ?? now
            if now.timeIntervalSince(fakeStart!) > 5, now.timeIntervalSince(fakeStart!) < 60 {
                active.append((-1, app.name, 0))
            }
        }

        let pids = Set(active.map(\.pid))
        for pid in since.keys where !pids.contains(pid) {
            since[pid] = nil
            if announced.remove(pid) != nil, announced.isEmpty { onCallEnded?() }
        }
        for item in active {
            let start = since[item.pid] ?? now
            since[item.pid] = start
            guard !announced.contains(item.pid), now.timeIntervalSince(start) >= item.delay else { continue }
            announced.insert(item.pid)
            onCallStarted?(item.name)
        }
    }

    /// True as long as a known video call app holds the microphone.
    var callInProgress: Bool { !announced.isEmpty }

    struct AudioProcess {
        var pid: pid_t
        var bundleID: String
    }

    /// The processes (other than Plume) currently reading an audio input.
    nonisolated static func processesUsingInput() -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        let me = getpid()
        return objects.compactMap { object in
            guard flag(kAudioProcessPropertyIsRunningInput, of: object) else { return nil }
            let pid = pid_t(number(kAudioProcessPropertyPID, of: object))
            guard pid != me, pid > 0, let bundle = string(kAudioProcessPropertyBundleID, of: object) else { return nil }
            return AudioProcess(pid: pid, bundleID: bundle)
        }
    }

    nonisolated private static func flag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        number(selector, of: object) != 0
    }

    nonisolated private static func number(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Int32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    nonisolated private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        let text = value as String
        return text.isEmpty ? nil : text
    }
}
