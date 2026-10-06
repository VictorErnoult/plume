import Foundation

/// Buffer of mono 16 kHz samples, fed by the audio thread and read by the transcription.
public final class SampleBuffer: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    public init() {
        storage.reserveCapacity(SpeechEngine.sampleRate * 120)
    }

    public func append(_ samples: [Float]) {
        lock.lock()
        storage.append(contentsOf: samples)
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    public var duration: Double { Double(count) / Double(SpeechEngine.sampleRate) }

    public func slice(_ range: Range<Int>) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let lower = max(0, min(range.lowerBound, storage.count))
        let upper = max(lower, min(range.upperBound, storage.count))
        return Array(storage[lower..<upper])
    }

    public func all() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

public enum AudioLevel {
    /// RMS level of a block of samples.
    public static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// True if no 100 ms frame exceeds the speech threshold.
    public static func isSilent(_ samples: [Float], threshold: Float = 0.006) -> Bool {
        firstActiveFrame(samples, threshold: threshold) == nil
    }

    /// Index of the first sample of a 100 ms frame above the threshold.
    public static func firstActiveFrame(_ samples: [Float], threshold: Float = 0.006) -> Int? {
        let frame = SpeechEngine.sampleRate / 10
        var i = 0
        while i < samples.count {
            let end = min(i + frame, samples.count)
            if rms(samples[i..<end]) > threshold { return i }
            i = end
        }
        return nil
    }
}

/// Live transcription over a sliding window.
///
/// On each pass, everything not yet "committed" is transcribed again (at most ~13 s).
/// As soon as the window contains a clear pause, the text before it is committed and will
/// no longer move; the rest is "volatile" and can still be corrected on the next pass.
public actor LiveTranscriber {
    public struct State: Sendable, Equatable {
        /// Committed text, stable.
        public var committed: String
        /// Text of the current window, liable to change.
        public var volatile: String

        public var full: String {
            [committed, volatile].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private let engine: SpeechEngine
    private let buffer: SampleBuffer
    private let sampleRate = Double(SpeechEngine.sampleRate)

    private var committedSample = 0
    private var committedText = ""
    private var volatileText = ""
    private var processedCount = 0

    /// Maximum duration of uncommitted audio sent to the model (its native input is 15 s).
    private let maxWindow: Double
    /// Already committed audio replayed before the window, so the model keeps the thread of the sentence.
    private let leftContext = 2.0
    /// Duration from which we look for a pause to commit at.
    private let commitAfter: Double
    /// End of the window left volatile: the model lacks context on the last words.
    private let tailKeep = 1.2

    /// - Parameter eager: shorter windows, committed earlier: each pass costs less
    ///   and the text arrives faster, at the price of a bit of context (typing as you dictate).
    public init(engine: SpeechEngine, buffer: SampleBuffer, eager: Bool = false) {
        self.engine = engine
        self.buffer = buffer
        maxWindow = eager ? 9 : 12
        commitAfter = eager ? 2.2 : 3.5
    }

    public var state: State { State(committed: committedText, volatile: volatileText) }

    /// One transcription pass. Returns `nil` if nothing new was captured.
    public func tick() async -> State? {
        let total = buffer.count
        guard total - processedCount >= Int(0.3 * sampleRate) else { return nil }
        processedCount = total

        let end = min(total, committedSample + Int(maxWindow * sampleRate))
        guard end > committedSample else { return nil }
        let truncated = end < total
        let fresh = buffer.slice(committedSample..<end)

        // Nothing spoken since the last commit: move on, keeping half a second.
        guard let firstActive = AudioLevel.firstActiveFrame(fresh) else {
            committedSample = max(committedSample, end - Int(0.5 * sampleRate))
            volatileText = ""
            return state
        }
        // Skip the initial silence so it isn't transcribed again on every pass.
        committedSample += max(0, firstActive - Int(0.3 * sampleRate))

        let contextSamples = min(Int(leftContext * sampleRate), committedSample)
        let windowStart = committedSample - contextSamples
        let window = buffer.slice(windowStart..<end)
        guard let output = try? await engine.transcribe(window) else { return state }

        // The context words are already committed: keep only what follows.
        let contextDuration = Double(contextSamples) / sampleRate
        let words = output.words.filter { ($0.start + $0.end) / 2 >= contextDuration }
        let windowDuration = Double(window.count) / sampleRate
        let freshDuration = windowDuration - contextDuration

        guard !words.isEmpty else {
            volatileText = ""
            if freshDuration > commitAfter {
                committedSample = end - Int(1.0 * sampleRate)
            }
            return state
        }

        if freshDuration >= commitAfter || truncated,
            let cut = commitIndex(
                words: words, windowDuration: windowDuration, freshDuration: freshDuration, force: truncated)
        {
            let head = words[..<cut].map(\.text).joined(separator: " ")
            committedText = [committedText, head].filter { !$0.isEmpty }.joined(separator: " ")
            let next = cut < words.count ? words[cut].start : min(windowDuration, words[cut - 1].end + 0.6)
            let cutTime = (words[cut - 1].end + next) / 2
            committedSample = windowStart + Int(cutTime * sampleRate)
            volatileText = words[cut...].map(\.text).joined(separator: " ")
        } else {
            volatileText = words.map(\.text).joined(separator: " ")
        }
        return state
    }

    /// End of recording: everything left is transcribed and committed at once.
    public func finish() async -> State {
        let total = buffer.count
        guard total > committedSample else {
            volatileText = ""
            return state
        }
        let contextSamples = min(Int(leftContext * sampleRate), committedSample)
        let windowStart = committedSample - contextSamples
        let window = buffer.slice(windowStart..<total)
        volatileText = ""
        guard !AudioLevel.isSilent(Array(window)), let output = try? await engine.transcribe(window) else { return state }
        let contextDuration = Double(contextSamples) / sampleRate
        let words = output.words.filter { ($0.start + $0.end) / 2 >= contextDuration }
        let tail = words.map(\.text).joined(separator: " ")
        committedText = [committedText, tail].filter { !$0.isEmpty }.joined(separator: " ")
        committedSample = total
        processedCount = total
        return state
    }

    /// Number of words to commit, or `nil` if no clean cut exists yet.
    ///
    /// We prefer to cut at a sentence end or a real pause: cutting in the middle
    /// of a sentence deprives the next window of its context and degrades recognition.
    private func commitIndex(words: [Word], windowDuration: Double, freshDuration: Double, force: Bool) -> Int? {
        let limit = force ? windowDuration : windowDuration - tailKeep
        var strong: Int?
        var weak: Int?
        var widest: (index: Int, gap: Double)?
        for i in 1..<max(1, words.count) {
            let previous = words[i - 1]
            guard previous.end <= limit else { break }
            let gap = words[i].start - previous.end
            let endsSentence = previous.text.last.map { ".?!…".contains($0) } ?? false
            if (endsSentence && gap >= 0.2) || gap >= 0.7 { strong = i }
            if gap >= 0.3 { weak = i }
            if gap > (widest?.gap ?? -1) { widest = (i, gap) }
        }
        // Silence after the last word: everything that was said can be committed.
        if let last = words.last, windowDuration - last.end >= 0.9 { return words.count }
        if let strong { return strong }
        // Continuous speech: near saturation, settle for a breath.
        if force || freshDuration >= maxWindow - 3 {
            return weak ?? widest?.index
        }
        return nil
    }
}
