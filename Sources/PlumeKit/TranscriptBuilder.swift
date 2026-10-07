import Foundation

/// Assembles timestamped words and diarization into readable speaker turns.
public enum TranscriptBuilder {
    /// Pause beyond which the same speaker opens a new paragraph.
    public static let paragraphGap = 2.5

    /// The device owner: "Me", or "Moi" in French.
    public static var meName: String { tr("Me") }

    /// "Speaker 1", or "Interlocuteur 1" in French.
    public static func speakerName(_ index: Int) -> String { "\(tr("Speaker")) \(index)" }

    /// Recognizes the owner whatever the language they were named in.
    public static func isMe(_ speaker: String) -> Bool { speaker == "Moi" || speaker == "Me" }

    /// Assigns each word to a speaker, then groups them into speaker turns.
    /// - Parameters:
    ///   - words: timestamped words of a channel.
    ///   - turns: diarization result for this channel (empty = single speaker).
    ///   - names: display name for each speaker identifier.
    ///   - fallback: name used without diarization.
    public static func segments(
        words: [Word], turns: [SpeakerTurn], names: [String: String], fallback: String, channel: AudioChannel
    ) -> [Segment] {
        guard !words.isEmpty else { return [] }
        var labels = words.map { word -> String in
            guard let id = speaker(at: (word.start + word.end) / 2, in: turns) else { return fallback }
            return names[id] ?? fallback
        }
        smooth(&labels, words: words)

        var out: [Segment] = []
        var current: (speaker: String, start: Double, end: Double, texts: [String])?
        func flush() {
            guard let c = current else { return }
            out.append(
                Segment(
                    id: out.count, speaker: c.speaker, channel: channel, start: c.start, end: c.end,
                    text: c.texts.joined(separator: " ")))
        }
        for (word, label) in zip(words, labels) {
            if let c = current, c.speaker == label, word.start - c.end < paragraphGap {
                current = (c.speaker, c.start, word.end, c.texts + [word.text])
            } else {
                flush()
                current = (label, word.start, word.end, [word.text])
            }
        }
        flush()
        return out
    }

    /// Active speaker at time `t`: the turn that contains it, otherwise the closest in time.
    public static func speaker(at t: Double, in turns: [SpeakerTurn]) -> String? {
        var nearest: (id: String, distance: Double)?
        for turn in turns {
            if t >= turn.start && t <= turn.end { return turn.speaker }
            let distance = t < turn.start ? turn.start - t : t - turn.end
            if distance < (nearest?.distance ?? .infinity) {
                nearest = (turn.speaker, distance)
            }
        }
        return nearest?.id
    }

    /// One or two isolated words attributed to someone else in the middle of a sentence are
    /// almost always a boundary error: give them back to the surrounding speaker.
    static func smooth(_ labels: inout [String], words: [Word]) {
        guard labels.count >= 3 else { return }
        var i = 1
        while i < labels.count - 1 {
            var j = i
            while j < labels.count - 1, labels[j] == labels[i] { j += 1 }
            let runLength = j - i
            let before = labels[i - 1]
            if labels[i] != before, runLength <= 2, labels[j] == before {
                let endsSentenceBefore = words[i - 1].text.last.map { ".?!…".contains($0) } ?? false
                let endsSentenceInside = words[j - 1].text.last.map { ".?!…".contains($0) } ?? false
                if !endsSentenceBefore && !endsSentenceInside {
                    for k in i..<j { labels[k] = before }
                }
            }
            i = max(j, i + 1)
        }
    }

    /// Realigns each speaker change on a natural break in the speech.
    ///
    /// Diarization places voice changes to within a few tenths of a second, which
    /// often leaves a word or two on the wrong side ("il y | a tellement de…"). Around
    /// each change, we therefore look for the real boundary: a pause, or a sentence end.
    static func snap(_ labels: inout [String], words: [Word], reach: Int = 4) {
        guard labels.count >= 2 else { return }
        /// Quality of a boundary placed just before word `index`: a pause, a sentence end.
        func quality(_ index: Int) -> Double {
            let previous = words[index - 1]
            var score = min(max(0, words[index].start - previous.end), 1.0)
            if let last = previous.text.last {
                if ".?!…".contains(last) { score += 0.6 } else if ",;:".contains(last) { score += 0.15 }
            }
            return score
        }
        /// Gap, in seconds, between time `moment` and the break located before word `index`.
        func distance(_ index: Int, from moment: Double) -> Double {
            let start = words[index - 1].end
            let end = words[index].start
            if moment < start { return start - moment }
            if moment > end { return moment - end }
            return 0
        }
        var index = 1
        while index < labels.count {
            guard labels[index] != labels[index - 1] else {
                index += 1
                continue
            }
            let left = labels[index - 1]
            let right = labels[index]
            // Possible positions for the boundary: as long as we stay within the left (going back)
            // or right (going forward) speaker's turn, a few words at most.
            var candidates: [Int] = []
            var back = index - 1
            while back >= 1, index - back <= reach, labels[back] == left {
                candidates.append(back)
                back -= 1
            }
            var forward = index + 1
            while forward < labels.count, forward - index <= reach, labels[forward - 1] == right {
                candidates.append(forward)
                forward += 1
            }

            // Diarization is rarely wrong by more than half a second: a break
            // far from the time it indicates must be clearly better to win.
            let moment = (words[index - 1].end + words[index].start) / 2
            var best = index
            var bestScore = quality(index)
            for candidate in candidates {
                // The last word before a pause "lasts" a long time in the timestamps: the
                // gap is capped at three tenths of a second per word crossed.
                let away = min(distance(candidate, from: moment), 0.3 * Double(abs(candidate - index)))
                guard away <= 2 else { continue }
                let score = quality(candidate) - 1.2 * away
                if score > bestScore + 0.12 {
                    best = candidate
                    bestScore = score
                }
            }
            if best < index {
                for k in best..<index { labels[k] = right }
            } else if best > index {
                for k in index..<best { labels[k] = left }
            }
            index = max(best, index) + 1
        }
    }

    /// Display names in order of first speaking: "Speaker 1", "2"…
    public static func names(for turns: [SpeakerTurn], startingAt first: Int = 1, me: String? = nil) -> [String: String] {
        var names: [String: String] = [:]
        var next = first
        for turn in turns where names[turn.speaker] == nil {
            if turn.speaker == me {
                names[turn.speaker] = meName
            } else {
                names[turn.speaker] = speakerName(next)
                next += 1
            }
        }
        return names
    }

    /// Merges several channels into a single chronological thread.
    public static func merge(_ channels: [[Segment]]) -> [Segment] {
        let sorted = channels.flatMap { $0 }.sorted { $0.start < $1.start }
        return sorted.enumerated().map { index, segment in
            var s = segment
            s.id = index
            return s
        }
    }

    /// Run of words by the same speaker on a channel, before formatting.
    public struct Run: Sendable, Equatable {
        public var speaker: String
        public var channel: AudioChannel
        public var words: [Word]

        public var start: Double { words.first?.start ?? 0 }
        public var end: Double { words.last?.end ?? 0 }
        public var text: String { words.map(\.text).joined(separator: " ") }

        public init(speaker: String, channel: AudioChannel, words: [Word]) {
            self.speaker = speaker
            self.channel = channel
            self.words = words
        }
    }

    /// Assigns each word of a channel to a speaker and groups consecutive words.
    /// - Parameter label: name to give to a diarization speaker identifier
    ///   (`nil` when no turn was detected).
    public static func runs(
        words: [Word], turns: [SpeakerTurn], channel: AudioChannel, gap: Double = paragraphGap,
        label: (String?) -> String
    ) -> [Run] {
        guard !words.isEmpty else { return [] }
        var labels = words.map { label(speaker(at: ($0.start + $0.end) / 2, in: turns)) }
        smooth(&labels, words: words)
        snap(&labels, words: words)
        var runs: [Run] = []
        for (word, speaker) in zip(words, labels) {
            if let last = runs.last, last.speaker == speaker, word.start - last.end < gap {
                runs[runs.count - 1].words.append(word)
            } else {
                runs.append(Run(speaker: speaker, channel: channel, words: [word]))
            }
        }
        return runs
    }

    private static func endsSentence(_ word: Word) -> Bool {
        word.text.last.map { ".?!…".contains($0) } ?? false
    }

    /// Interleaves the speaking turns of all channels in the order they happened.
    ///
    /// When someone speaks up in the middle of another's long turn, that turn is cut at the end
    /// of the nearest sentence: the interruption appears in its place in the conversation
    /// instead of being pushed back after the monologue.
    public static func interleave(_ runs: [Run], gap: Double = paragraphGap) -> [Run] {
        // Each chunk carries the time that fixes its place in the thread: its start, or, for the
        // rest of a cut turn, the time of the interruption that cut it (the rest comes after).
        var keyed: [(key: Double, run: Run)] = []
        for run in runs {
            // Times when another speaker takes the floor during this turn.
            let interruptions = runs
                .filter { $0.speaker != run.speaker && $0.start > run.start + 0.5 && $0.start < run.end - 0.5 }
                .map(\.start)
                .sorted()
            var remaining = run.words
            var key = run.start
            for moment in interruptions {
                guard let cut = splitIndex(in: remaining, near: moment) else { continue }
                keyed.append((key, Run(speaker: run.speaker, channel: run.channel, words: Array(remaining[..<cut]))))
                remaining = Array(remaining[cut...])
                key = max(remaining.first?.start ?? moment, moment + 0.001)
            }
            if !remaining.isEmpty {
                keyed.append((key, Run(speaker: run.speaker, channel: run.channel, words: remaining)))
            }
        }
        let pieces = keyed.sorted { $0.key < $1.key }.map(\.run)

        // Two consecutive chunks by the same speaker, with nobody between them, are glued back together.
        var merged: [Run] = []
        for piece in pieces {
            if let last = merged.last, last.speaker == piece.speaker, piece.start - last.end < gap {
                merged[merged.count - 1].words.append(contentsOf: piece.words)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// Index at which to cut `words` to let an interruption through at time `moment`:
    /// the nearest sentence end, failing that the nearest pause.
    static func splitIndex(in words: [Word], near moment: Double) -> Int? {
        guard words.count >= 4 else { return nil }
        var best: (index: Int, score: Double)?
        for index in 2...(words.count - 2) {
            let previous = words[index - 1]
            let gap = words[index].start - previous.end
            let sentence = endsSentence(previous)
            guard sentence || gap >= 0.35 else { continue }
            let distance = abs(previous.end - moment)
            guard distance <= 5 else { continue }
            // A sentence end beats a mere pause, at equal distance.
            let score = distance + (sentence ? 0 : 2.5)
            if score < (best?.score ?? .infinity) { best = (index, score) }
        }
        return best?.index
    }

    /// Converts speaking turns into segments, naming the speakers in the order
    /// they speak: "Speaker 1", "2"…; `Me` keeps its name.
    public static func segments(from runs: [Run], me: Set<String> = []) -> [Segment] {
        var names: [String: String] = [:]
        var next = 1
        return runs.enumerated().map { index, run in
            let name: String
            if me.contains(run.speaker) || isMe(run.speaker) {
                name = meName
            } else if let known = names[run.speaker] {
                name = known
            } else {
                name = speakerName(next)
                names[run.speaker] = name
                next += 1
            }
            // A speaker turn starts with a capital, even when the model ran it on
            // without punctuation from someone else's sentence.
            var text = run.text
            if let first = text.first, first.isLowercase { text = first.uppercased() + text.dropFirst() }
            return Segment(id: index, speaker: name, channel: run.channel, start: run.start, end: run.end, text: text)
        }
    }

    /// Removes from the microphone channel what is only the echo of the system audio
    /// (meeting without earphones: the speakers play back into the microphone).
    ///
    /// A microphone segment is an echo only if it repeats, at the same moment, the same sequences
    /// of words as the system audio. Sharing common vocabulary is not enough: a real
    /// reply ("d'accord, je vois ce que tu veux dire") must stay.
    public static func removingEcho(mic: [Segment], systemWords: [Word]) -> [Segment] {
        guard !systemWords.isEmpty else { return mic }
        return mic.filter { segment in
            let spoken = tokens(segment.text)
            guard spoken.count >= 4 else { return true }
            let nearby = systemWords
                .filter { $0.end >= segment.start - 1.5 && $0.start <= segment.end + 1.5 }
                .flatMap { tokens($0.text) }
            guard nearby.count >= 3 else { return true }
            let heard = Set(zip(nearby, nearby.dropFirst()).map { "\($0) \($1)" })
            let pairs = zip(spoken, spoken.dropFirst()).map { "\($0) \($1)" }
            let shared = pairs.filter(heard.contains).count
            return Double(shared) / Double(pairs.count) < 0.5
        }
    }

    /// Same filter, applied to the microphone's speaking turns before formatting.
    public static func removingEcho(mic: [Run], systemWords: [Word]) -> [Run] {
        let kept = Set(
            removingEcho(
                mic: mic.enumerated().map {
                    Segment(id: $0.offset, speaker: $0.element.speaker, channel: .mic, start: $0.element.start, end: $0.element.end, text: $0.element.text)
                }, systemWords: systemWords
            ).map(\.id))
        return mic.enumerated().filter { kept.contains($0.offset) }.map(\.element)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Plain text of a conversation: timestamped dialogue if there are several voices, paragraphs otherwise.
    public static func text(for segments: [Segment]) -> String {
        if speakers(in: segments).count > 1 {
            return segments
                .map { "\($0.speaker) [\(Format.clock($0.start))] : \($0.text)" }
                .joined(separator: "\n\n")
        }
        return segments.map(\.text).joined(separator: "\n\n")
    }

    public static func speakers(in segments: [Segment]) -> [String] {
        var seen: [String] = []
        for s in segments where !seen.contains(s.speaker) { seen.append(s.speaker) }
        return seen
    }
}

/// Voiceprint of the owner, learned over the dictations, to recognize them
/// ("Me") among the speakers of a meeting.
public struct Voiceprint: Codable, Sendable {
    public var embedding: [Float]
    public var samples: Int

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denominator = (na * nb).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }

    /// Integrates a new measurement (running average, capped to follow changes in the voice).
    public mutating func add(_ other: [Float]) {
        guard other.count == embedding.count else { return }
        let weight = Float(min(samples, 30))
        for i in 0..<embedding.count {
            embedding[i] = (embedding[i] * weight + other[i]) / (weight + 1)
        }
        samples += 1
    }

    /// Identifier of the speaker matching the voiceprint, if one is close enough.
    public func match(in embeddings: [String: [Float]], threshold: Float = 0.45) -> String? {
        let scored = embeddings.map { ($0.key, Self.cosine(embedding, $0.value)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= threshold else { return nil }
        return best.0
    }
}
