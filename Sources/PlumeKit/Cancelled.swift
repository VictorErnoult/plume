import Foundation

/// A cancelled recording, kept aside for a while: one stray Esc must not cost
/// a whole meeting.
public struct CancelledRecording: Codable, Sendable, Identifiable, Equatable {
    /// Session identifier, the same one its transcript would have had.
    public var id: String
    public var createdAt: Date
    public var cancelledAt: Date
    public var mode: RecordingMode
    public var duration: Double
    /// Frontmost app when the recording was made.
    public var app: String?
    /// Transcript made in the background after cancelling (dictations only), or `nil`.
    public var text: String?
    public var rawText: String?
    /// Audio file names, relative to the cancelled folder.
    public var audioFiles: [String]

    public init(
        id: String, createdAt: Date, cancelledAt: Date = Date(), mode: RecordingMode, duration: Double,
        app: String? = nil, text: String? = nil, rawText: String? = nil, audioFiles: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.cancelledAt = cancelledAt
        self.mode = mode
        self.duration = duration
        self.app = app
        self.text = text
        self.rawText = rawText
        self.audioFiles = audioFiles
    }

    /// Start of the text, for lists.
    public var preview: String? {
        guard let text, !text.isEmpty else { return nil }
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
    }
}

/// Cancelled recordings, stored apart in a hidden folder of the library
/// (`~/Plume/.cancelled/`, `.annules` up to 1.0.1): they appear neither in the index, nor in
/// `dernier.md`, nor in `plume last`, and they disappear on their own after the delay chosen
/// in the settings.
///
///     ~/Plume/.cancelled/
///       2026-10-05_14-31-05.json       what is known about the recording
///       2026-10-05_14-31-05_mic.m4a    the microphone audio
///       2026-10-05_14-31-05_sys.m4a    the system audio (meeting)
public final class CancelledStore: @unchecked Sendable {
    public enum Failure: Error {
        /// The transcription found nothing.
        case nothingHeard
    }

    public let root: URL
    private let fm = FileManager.default
    private static let lock = NSRecursiveLock()

    public init(library: URL) {
        let old = library.appendingPathComponent(".annules", isDirectory: true)
        root = Migration.resolve(old: old, new: library.appendingPathComponent(".cancelled", isDirectory: true))
        // An older version run after the upgrade recreates `.annules`: fold it back in, so
        // nothing escapes the list or the purge.
        if root != old { Migration.merge(folder: old, into: root) }
    }

    private func jsonURL(forID id: String) -> URL { root.appendingPathComponent(id + ".json") }

    public func audioURLs(for recording: CancelledRecording) -> [URL] {
        recording.audioFiles.map { root.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    /// Sets a cancelled recording aside. The audio is written first: a recording
    /// is only visible once complete.
    /// - Parameter system: the system audio and its offset from the start.
    public func keep(_ recording: CancelledRecording, mic: [Float], system: (samples: [Float], offset: Double)? = nil) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var recording = recording
        recording.audioFiles = []
        let micName = "\(recording.id)_mic.m4a"
        try AudioIO.writeM4A(mic, to: root.appendingPathComponent(micName))
        recording.audioFiles.append(micName)
        if let system, !AudioLevel.isSilent(system.samples) {
            // Initial silence equal to the offset: the two tracks stay aligned with each other.
            let lead = [Float](repeating: 0, count: Int(system.offset * Double(SpeechEngine.sampleRate)))
            let name = "\(recording.id)_sys.m4a"
            if (try? AudioIO.writeM4A(lead + system.samples, to: root.appendingPathComponent(name))) != nil {
                recording.audioFiles.append(name)
            }
        }
        try write(recording)
    }

    /// Rewrites the record of a recording that is still there (text found afterwards).
    public func update(_ recording: CancelledRecording) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard fm.fileExists(atPath: jsonURL(forID: recording.id).path) else { return }
        try? write(recording)
    }

    private func write(_ recording: CancelledRecording) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: jsonURL(forID: recording.id), options: .atomic)
    }

    /// From most recently cancelled to oldest.
    public func list() -> [CancelledRecording] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { name in
                (try? Data(contentsOf: root.appendingPathComponent(name)))
                    .flatMap { try? decoder.decode(CancelledRecording.self, from: $0) }
            }
            .sorted { $0.cancelledAt > $1.cancelledAt }
    }

    public func load(id: String) -> CancelledRecording? {
        list().first { $0.id == id }
    }

    public func delete(id: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name.hasPrefix(id + "_") || name == id + ".json" {
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
    }

    /// Deletes what was cancelled before `cutoff`.
    @discardableResult
    public func purge(cancelledBefore cutoff: Date) -> Int {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let expired = list().filter { $0.cancelledAt < cutoff }
        expired.forEach { delete(id: $0.id) }
        return expired.count
    }

    /// Transcribes (if needed) a cancelled recording and files it in the library, as
    /// if it had been finished normally. It then leaves the cancelled ones.
    /// - Parameter save: false for a dictation when history is off: the text is
    ///   only returned, nothing is filed.
    public func restore(
        _ recording: CancelledRecording, save: Bool = true, settings: PlumeSettings = .shared,
        engine: SpeechEngine = .shared
    ) async throws -> Transcript {
        let store = settings.store
        let urls = audioURLs(for: recording)
        guard let micURL = urls.first(where: { $0.lastPathComponent.hasSuffix("_mic.m4a") }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        // The original identifier, unless a transcript took it in the meantime.
        let id = store.load(id: recording.id) == nil ? recording.id : store.makeID(for: recording.createdAt)
        var transcript: Transcript
        if recording.mode == .meeting {
            try await engine.prepare(model: settings.model)
            var channels = [ChannelAudio(channel: .mic, samples: try AudioIO.loadSamples(micURL))]
            if let sys = urls.first(where: { $0.lastPathComponent.hasSuffix("_sys.m4a") }),
                let samples = try? AudioIO.loadSamples(sys)
            {
                channels.append(ChannelAudio(channel: .system, samples: samples))
            }
            let result = try await Pipeline.conversation(
                channels: channels, engine: engine, voiceprint: VoiceprintStore.load(), ownerOnMic: true)
            transcript = Transcript(
                id: id, createdAt: recording.createdAt, mode: .meeting, duration: recording.duration,
                engine: await engine.modelName, text: result.text, rawText: result.rawText,
                segments: result.segments, speakers: result.speakers, app: recording.app)
        } else {
            var text = recording.text ?? ""
            var raw = recording.rawText ?? text
            if recording.text == nil {
                try await engine.prepare(model: settings.model)
                let result = try await Pipeline.dictation(
                    samples: try AudioIO.loadSamples(micURL), engine: engine, options: DictationOptions(settings: settings))
                text = result.text
                raw = result.raw
            }
            transcript = Transcript(
                id: id, createdAt: recording.createdAt, mode: .dictation, duration: recording.duration,
                engine: await engine.modelName, text: text, rawText: raw, app: recording.app)
        }

        // Nothing intelligible: the recording stays among the cancelled, it can still be listened to.
        guard !transcript.text.isEmpty else { throw Failure.nothingHeard }

        if save {
            if settings.keepAudio {
                let directory = try store.ensureDirectory(forID: id)
                for url in urls {
                    let suffix = url.lastPathComponent.hasSuffix("_sys.m4a") ? "sys" : "mic"
                    let name = "\(id)_\(suffix).m4a"
                    if (try? fm.copyItem(at: url, to: directory.appendingPathComponent(name))) != nil {
                        transcript.audioFiles.append(name)
                    }
                }
            }
            try store.save(transcript)
        }
        delete(id: recording.id)
        return transcript
    }
}
