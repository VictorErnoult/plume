import Foundation

/// Transcribes an existing audio file and files it in the library
/// (drag and drop, menu, command line).
public enum Importer {
    public static let audioExtensions: Set<String> = [
        "m4a", "wav", "mp3", "caf", "aac", "aiff", "aif", "flac", "mp4", "mov", "qta", "opus", "ogg",
    ]

    public static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// - Parameters:
    ///   - mode: `.dictation` produces a clean single-voice text; the other modes
    ///     separate the speakers.
    ///   - save: writes the transcript (and the audio, if the settings ask for it) to the library.
    public static func importAudio(
        at url: URL, mode: RecordingMode, device: String, date: Date = Date(), save: Bool = true,
        settings: PlumeSettings = .shared, engine: SpeechEngine = .shared
    ) async throws -> Transcript {
        try await engine.prepare(model: settings.model)
        let samples = try AudioIO.loadSamples(url)
        let duration = Double(samples.count) / Double(SpeechEngine.sampleRate)
        let store = settings.store
        let id = store.makeID(for: date)

        var transcript: Transcript
        if mode == .dictation {
            let result = try await Pipeline.dictation(
                samples: samples, engine: engine, options: DictationOptions(settings: settings))
            transcript = Transcript(
                id: id, createdAt: date, mode: .dictation, device: device, duration: duration,
                engine: await engine.modelName, text: result.text, rawText: result.raw)
        } else {
            let result = try await Pipeline.conversation(
                channels: [ChannelAudio(channel: .mic, samples: samples)], engine: engine,
                voiceprint: VoiceprintStore.load(), ownerOnMic: false)
            transcript = Transcript(
                id: id, createdAt: date, mode: mode, device: device, duration: duration,
                engine: await engine.modelName, text: result.text, rawText: result.rawText,
                segments: result.segments, speakers: result.speakers)
        }

        guard save else { return transcript }
        if settings.keepAudio {
            let dir = try store.ensureDirectory(forID: id)
            let name = "\(id)_mic.m4a"
            if (try? AudioIO.writeM4A(samples, to: dir.appendingPathComponent(name))) != nil {
                transcript.audioFiles = [name]
            }
        }
        try store.save(transcript)
        return transcript
    }
}
