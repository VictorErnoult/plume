import AVFoundation
import Foundation
import PlumeKit

/// Controls the running app from the command line
/// (`plume toggle dictee`, `plume stop`…), useful for Raycast, Shortcuts or a Stream Deck.
enum Remote {
    /// Command channel. The `PLUME_CHANNEL` variable opens another one, to drive a
    /// trial instance without touching the installed app.
    static let notification = Notification.Name(
        "studio.brigode.plume.command" + (ProcessInfo.processInfo.environment["PLUME_CHANNEL"].map { "." + $0 } ?? ""))

    static func send(_ command: String) {
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: command, userInfo: nil, deliverImmediately: true)
    }

    /// Return channel: the text of a dictation requested by `plume listen` or the MCP tool.
    static let resultNotification = Notification.Name(notification.rawValue + ".result")

    /// Hands a capture's text to whoever is waiting: written to a temporary file (a
    /// notification can't carry a long text), whose path is notified. The recipient
    /// deletes the file once read.
    static func deliver(_ transcript: Transcript) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plume-capture-\(transcript.id).txt")
        guard (try? transcript.text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        DistributedNotificationCenter.default().postNotificationName(
            resultNotification, object: url.path, userInfo: nil, deliverImmediately: true)
    }

    /// Island diagnostic, wired up by the app.
    nonisolated(unsafe) static var onSnapshot: (() -> Void)?
    /// Diagnostic: open (true) or close (false) the island's drawer without the mouse.
    nonisolated(unsafe) static var onDrawer: ((Bool) -> Void)?

    /// What a command word asks the app to do.
    enum Action: Equatable {
        case toggleDictation, toggleMeeting, toggleCapture, toggleTransform
        case stop, cancel, pause, pasteLast, restore, open, snapshot
        case drawer(open: Bool)
        case selftestSystemAudio, selftestMic
    }

    /// Maps a command word to its action. The channel words `toggle-dictee`/`toggle-reunion`
    /// stay French (both ends ship together); the drawer words are English, with the old
    /// French ones still accepted.
    static func action(for command: String) -> Action? {
        switch command {
        case "toggle-dictee": return .toggleDictation
        case "toggle-reunion": return .toggleMeeting
        case "toggle-capture": return .toggleCapture
        case "toggle-transform": return .toggleTransform
        case "stop": return .stop
        case "cancel": return .cancel
        case "pause": return .pause
        case "paste-last": return .pasteLast
        case "restore": return .restore
        case "open": return .open
        case "snapshot": return .snapshot
        case "drawer-open", "tiroir-ouvert": return .drawer(open: true)
        case "drawer-close", "tiroir-ferme": return .drawer(open: false)
        case "selftest-system-audio": return .selftestSystemAudio
        case "selftest-mic": return .selftestMic
        default: return nil
        }
    }

    @MainActor
    static func listen(session: SessionController, onOpen: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            guard let command = note.object as? String, let action = action(for: command) else { return }
            Task { @MainActor in
                switch action {
                case .toggleDictation: session.toggle(.dictation)
                case .toggleMeeting: session.toggle(.meeting)
                // Dictation without pasting: the text waits in the library (`plume listen`, MCP tool).
                case .toggleCapture: session.toggle(.dictation, intent: .capture)
                case .toggleTransform: session.toggle(.dictation, intent: .transform)
                case .stop: session.stop()
                case .cancel: session.cancel()
                case .pause: session.togglePause()
                case .pasteLast: session.pasteLast()
                case .restore: session.restoreCancelled()
                case .open: onOpen()
                case .snapshot: onSnapshot?()
                case .drawer(let open): onDrawer?(open)
                case .selftestSystemAudio: SelfTest.systemAudio()
                case .selftestMic: SelfTest.microphone()
                }
            }
        }
    }
}

/// Test hooks, enabled by environment variables: replay a file in
/// place of the microphone or system audio, and paste nothing. No effect in normal use.
enum TestHooks {
    private static let environment = ProcessInfo.processInfo.environment

    static var fakeMic: URL? { environment["PLUME_FAKE_MIC"].map { URL(fileURLWithPath: $0) } }
    static var fakeSystem: URL? { environment["PLUME_FAKE_SYSTEM"].map { URL(fileURLWithPath: $0) } }
    static var noPaste: Bool { environment["PLUME_NO_PASTE"] != nil }
    /// Invisible trial instance: no island, no icon, no global shortcuts, so as not to
    /// disturb the user or react to their own keystrokes during a trial run.
    static var headless: Bool { environment["PLUME_HEADLESS"] != nil }
    /// In invisible mode, still show the island (to check its drawing).
    static var showsIsland: Bool { !headless || environment["PLUME_SHOW_ISLAND"] != nil }
    static var verbose: Bool { environment["PLUME_VERBOSE"] != nil }
    /// Trial run of the update system by an invisible instance: immediate check,
    /// download and installation without an interface.
    static var updates: Bool { environment["PLUME_UPDATES"] != nil }

    static func log(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write(("[plume] " + message() + "\n").data(using: .utf8)!)
    }
}

/// App log: `~/Library/Logs/Plume/plume.log`.
enum Log {
    private static let queue = DispatchQueue(label: "plume.log")
    static let url: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Plume", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("plume.log")
    }()

    static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        TestHooks.log(message)
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// Audio source shared by the microphone, system audio and replayed files.
protocol AudioSource: AnyObject {
    var onSamples: (([Float]) -> Void)? { get set }
    func start() throws
    func stop()
}

extension MicCapture: AudioSource {}
extension SystemAudioCapture: AudioSource {}

/// Replays an audio file at real-time pace, as if it came from a microphone.
final class FileCapture: AudioSource {
    var onSamples: (([Float]) -> Void)?
    private let url: URL
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "plume.file-capture")

    init(url: URL) {
        self.url = url
    }

    func start() throws {
        let samples = try AudioIO.loadSamples(url)
        let chunk = SpeechEngine.sampleRate / 20  // 50 ms
        var offset = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if offset < samples.count {
                let end = min(offset + chunk, samples.count)
                self.onSamples?(Array(samples[offset..<end]))
                offset = end
            } else {
                // End of file: silence, like a microphone left open.
                self.onSamples?([Float](repeating: 0, count: chunk))
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

/// Check of system audio capture, recording nothing: opens the tap for three
/// seconds and logs what arrives.
@MainActor
enum SelfTest {
    private static var capture: SystemAudioCapture?

    private static var mic: MicCapture?

    /// Opens the microphone for a second and logs which one was used and whether it picks up sound.
    /// Nothing is recorded.
    static func microphone() {
        guard mic == nil, Permissions.microphoneGranted else {
            Log.write("mic test: permission missing or test already running")
            return
        }
        let capture = MicCapture()
        let lock = NSLock()
        var count = 0
        var peak: Float = 0
        capture.onSamples = { samples in
            let level = AudioLevel.rms(samples[...])
            lock.lock()
            count += samples.count
            peak = max(peak, level)
            lock.unlock()
        }
        do {
            try capture.start()
        } catch {
            Log.write("mic test: failed — \(error.localizedDescription)")
            return
        }
        mic = capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            capture.stop()
            mic = nil
            lock.lock()
            let seconds = Double(count) / Double(SpeechEngine.sampleRate)
            let level = peak
            lock.unlock()
            Log.write(String(format: "mic test: “%@”, %.2f s received in 1 s, peak level %.4f", capture.deviceName, seconds, level))
        }
    }

    static func systemAudio() {
        guard capture == nil else { return }
        let tap = SystemAudioCapture()
        let lock = NSLock()
        var count = 0
        var peak: Float = 0
        tap.onSamples = { samples in
            let level = AudioLevel.rms(samples[...])
            lock.lock()
            count += samples.count
            peak = max(peak, level)
            lock.unlock()
        }
        try? tap.start()
        capture = tap
        Log.write("system audio test: start requested")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            tap.stop()
            capture = nil
            lock.lock()
            let seconds = Double(count) / Double(SpeechEngine.sampleRate)
            let level = peak
            lock.unlock()
            Log.write(String(format: "system audio test: %.2f s received in 3 s, peak level %.4f", seconds, level))
        }
    }
}
