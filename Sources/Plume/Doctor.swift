import AVFoundation
import AppKit
import FluidAudio
import PlumeKit

/// `plume doctor` : un état des lieux lisible, pour comprendre pourquoi quelque chose ne marche pas.
enum Doctor {
    @MainActor
    static func run() async {
        let settings = PlumeSettings.shared
        func line(_ label: String, _ value: String) {
            CLI.emit(label.padding(toLength: 30, withPad: " ", startingAt: 0) + value)
        }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: PlumeSettings.bundleID)
        line(tr("App running"), running.isEmpty ? tr("no") : tr("yes"))
        line(tr("Library"), settings.libraryURL.path)
        line("Transcriptions", "\(settings.store.list().count)")
        line(tr("Model chosen"), settings.model == .custom ? tr("folder:") + " \(settings.customModelURL?.path ?? tr("none"))" : settings.model.rawValue)
        let cached = settings.model.isAvailableOffline(customDirectory: settings.customModelURL)
        line(settings.model == .custom ? tr("Complete folder") : tr("Model downloaded"), cached ? tr("yes") : tr("no (downloaded on first launch)"))
        line(tr("History"), settings.keepHistory ? (settings.keepAudio ? tr("text and audio") : tr("text only")) : tr("nothing is kept"))
        line(tr("Dictation shortcut"), HotkeyManager.describe(settings.dictationShortcut))
        line(tr("Meeting shortcut"), HotkeyManager.describe(settings.meetingShortcut))

        let mic: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = tr("granted")
        case .denied, .restricted: mic = tr("denied")
        default: mic = tr("not asked yet")
        }
        // Les autorisations dépendent du programme qui lance la commande : depuis un terminal,
        // ce sont celles du terminal, pas celles de l'app.
        line(tr("Microphone (this process)"), mic)
        line(tr("Accessibility (this process)"), Paster.isTrusted ? tr("enabled") : tr("not enabled"))
        let microphones = AudioDevices.inputs()
        line(tr("Microphone used by Plume"), AudioDevices.preferredInput(among: microphones)?.name ?? tr("system default input"))
        if let device = AVCaptureDevice.default(for: .audio) {
            line(tr("System default input"), device.localizedName)
        }
        for device in microphones {
            let kind = device.isBuiltIn ? tr("built-in") : (device.isBluetooth ? "Bluetooth" : tr("other"))
            line("  " + tr("available microphone"), "\(device.name) (\(kind))")
        }
        for screen in NSScreen.screens {
            let geometry = NotchGeometry(screen: screen)
            let notch = geometry.hasNotch
                ? tr("notch") + " \(Int(geometry.notchWidth)) × \(Int(geometry.topHeight)) pt"
                : String(format: tr("no notch (%ld pt bar)"), Int(geometry.topHeight))
            line(tr("Display") + " \(screen.localizedName)", "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt, \(notch)")
        }
        line(tr("Voiceprint"), VoiceprintStore.load().map { tr("learned from") + " \($0.samples) " + tr("dictation(s)") } ?? tr("not learned yet"))
        switch LocalAI.availability {
        case .available: line(tr("Local AI"), tr("Apple Intelligence available"))
        case .unavailable(let reason): line(tr("Local AI"), tr("unavailable") + " — \(reason)")
        }
        line(tr("Per-app rules"), "\(AppRuleStore.load().count)")
        let calls = MeetingDetector.processesUsingInput()
        line(tr("Apps using the microphone"), calls.isEmpty ? tr("no app") : calls.map(\.bundleID).joined(separator: ", "))
    }
}
