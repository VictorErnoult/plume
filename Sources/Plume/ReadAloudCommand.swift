import Foundation
import PlumeKit

/// `plume read-aloud`: reads standard input aloud, word for word or summarized first.
/// Everything it needs comes in through `Context`, so tests never touch real settings or models.
enum ReadAloudCommand {
    struct Options: Equatable {
        var summary = false
        var textOnly = false
        var json = false
        var engineID: String?
        var download: String?
        var evalFolder: String?
        var evalEngines: [String] = []
        var evalOut: String?
    }

    struct Context {
        var models: ReadAloudModels
        var catalog: [SummaryEngineEntry]
        var engineInUse: String
        var voiceID: String
        var speed: Double
        var options: SummaryOptions
        var interface: Language
    }

    static func parse(_ args: [String]) -> Options? {
        var options = Options()
        var rest = args[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--summary": options.summary = true
            case "--text": options.textOnly = true
            case "--json": options.json = true
            case "--engine": guard let value = rest.popFirst() else { return nil }; options.engineID = value
            case "--download": guard let value = rest.popFirst() else { return nil }; options.download = value
            case "--eval": guard let value = rest.popFirst() else { return nil }; options.evalFolder = value
            case "--engines":
                guard let value = rest.popFirst() else { return nil }
                options.evalEngines = value.split(separator: ",").map(String.init)
            case "--out": guard let value = rest.popFirst() else { return nil }; options.evalOut = value
            default: return nil
            }
        }
        return options
    }

    static func run(
        _ options: Options, context: Context, input: String,
        emit: @escaping (String) -> Void, fail: @escaping (String) -> Void
    ) async -> Int32 {
        do {
            if let item = options.download { return try await download(item, context: context, fail: fail) }
            // Task 14 replaces this with ReadAloudEvalCommand.
            if options.evalFolder != nil { throw ReadAloudError.unknownEngine }
            if options.summary { return try await summarize(input, options: options, context: context, emit: emit) }
            return try await readAloud(input, options: options, context: context, emit: emit)
        } catch {
            fail(error.localizedDescription)
            return 1
        }
    }

    private static func download(_ item: String, context: Context, fail: (String) -> Void) async throws -> Int32 {
        let target: DownloadItem = item == "voice" ? .voice : .engine(item)
        if case .engine(let id) = target, SummaryEngineCatalog.entry(id: id, in: context.catalog) == nil {
            throw ReadAloudError.unknownEngine
        }
        let shown = Percent()
        try await context.models.download(target, catalog: context.catalog) { fraction in
            if let percent = shown.advance(to: fraction) {
                FileHandle.standardError.write(Data((tr("Downloading…") + " \(percent) %\n").utf8))
            }
        }
        return 0
    }

    private static func readAloud(_ input: String, options: Options, context: Context, emit: (String) -> Void) async throws -> Int32 {
        let start = ContinuousClock.now
        let (language, sentences) = try ReadAloudPipeline.readAloud(input, interface: context.interface)
        if options.textOnly || options.json {
            if options.json {
                emit(try json(["mode": "readAloud", "language": language, "sentences": sentences, "truncated": false,
                               "timings": ["totalSeconds": seconds(since: start)]]))
            } else {
                sentences.forEach(emit)
            }
            return 0
        }
        let voice = SupertonicVoice(entry: VoiceCatalog.entry(id: context.voiceID), modelsDirectory: context.models.directory)
        try await voice.load()
        let events = AsyncThrowingStream<ReadAloudEvent, Error> { continuation in
            continuation.yield(.language(language))
            sentences.forEach { continuation.yield(.sentence($0)) }
            continuation.finish()
        }
        try await speak(events, voice: voice, speed: context.speed)
        return 0
    }

    private static func summarize(_ input: String, options: Options, context: Context, emit: (String) -> Void) async throws -> Int32 {
        let id = options.engineID ?? context.engineInUse
        guard let entry = SummaryEngineCatalog.entry(id: id, in: context.catalog) else {
            throw id.isEmpty ? ReadAloudError.engineNotInstalled : ReadAloudError.unknownEngine
        }
        guard context.models.isInstalled(entry) else { throw ReadAloudError.engineNotInstalled }
        let service = LlamaSummaryService(entry: entry, modelURL: context.models.modelURL(for: entry))
        let events = ReadAloudPipeline.summary(input, service: service, markers: entry.markers, options: context.options, interface: context.interface)

        if options.textOnly || options.json {
            var timings = Timings()
            var sentences: [String] = []
            var language = ""
            var truncated = false
            for try await event in events {
                timings.note(event)
                switch event {
                case .sentence(let sentence): sentences.append(sentence)
                case .language(let code): language = code
                case .truncated: truncated = true
                default: break
                }
            }
            if options.json {
                emit(try json(["mode": "summary", "engine": entry.id, "language": language, "sentences": sentences,
                               "truncated": truncated, "timings": timings.dictionary]))
            } else {
                emit(sentences.joined(separator: " "))
            }
            return 0
        }
        let voice = SupertonicVoice(entry: VoiceCatalog.entry(id: context.voiceID), modelsDirectory: context.models.directory)
        try await voice.load()
        try await speak(events, voice: voice, speed: context.speed)
        return 0
    }

    /// Synthesizes sentences as they come and plays them in order. Synthesis (~90× real time)
    /// runs ahead of playback, but at most three sentences ahead: a long read never holds all
    /// its audio in memory.
    private static func speak(_ events: AsyncThrowingStream<ReadAloudEvent, Error>, voice: SupertonicVoice, speed: Double) async throws {
        let player = ReadAloudPlayer(sampleRate: voice.sampleRate, rate: speed)
        try player.start()
        defer { player.stop() }
        let ahead = Permits(3)
        let (audio, sink) = AsyncThrowingStream<[Float], Error>.makeStream()
        let producer = Task {
            do {
                var language = "en"
                for try await event in events {
                    switch event {
                    case .language(let code): language = code
                    case .sentence(let sentence):
                        await ahead.acquire()
                        sink.yield(try await voice.speak(sentence, language: language))
                    default: break
                    }
                }
                sink.finish()
            } catch {
                sink.finish(throwing: error)
            }
        }
        defer { producer.cancel() }
        for try await samples in audio {
            await player.play(samples)
            await ahead.release()
        }
    }

    static func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Load, input reading, first sentence and total, from the pipeline's events.
    struct Timings {
        let start = ContinuousClock.now
        var load: Double?
        var readingInput: Double?
        var firstSentence: Double?
        private var loading = false

        mutating func note(_ event: ReadAloudEvent) {
            let now = ReadAloudCommand.seconds(since: start)
            switch event {
            case .loading: loading = true
            case .language: if loading, load == nil { load = now }
            case .summarizing: if readingInput == nil { readingInput = now }
            case .sentence: if firstSentence == nil { firstSentence = now }
            default: break
            }
        }

        var dictionary: [String: Double] {
            var values = ["totalSeconds": ReadAloudCommand.seconds(since: start)]
            if let load { values["loadSeconds"] = load }
            if let readingInput { values["readingInputSeconds"] = readingInput }
            if let firstSentence { values["firstSentenceSeconds"] = firstSentence }
            return values
        }
    }
}

/// A counting semaphore for async code: bounds how far synthesis runs ahead of playback.
actor Permits {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { available = count }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
    }
}

/// Whole-percent progress, printed only when it changes.
final class Percent: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1
    func advance(to fraction: Double) -> Int? {
        let percent = Int(fraction * 100)
        return lock.withLock { () -> Int? in
            guard percent > last else { return nil }
            last = percent
            return percent
        }
    }
}
