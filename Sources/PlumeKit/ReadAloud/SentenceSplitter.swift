import Foundation

/// Cuts text into sentences as it arrives: the voice starts on the first sentence while
/// the rest is still being written by the model or prepared.
///
/// Works on substrings and only scans up to the length limit, so a megabyte of text
/// splits in linear time.
public struct SentenceSplitter: Sendable {
    /// Beyond this, a sentence without an end is cut anyway: synthesis never waits on a huge piece.
    public let maxLength: Int
    /// Cap for the first sentence only: word-for-word reading starts on a short piece
    /// (Supertonic synthesizes in 70-character chunks).
    public let firstMaxLength: Int?
    private var pending = ""
    private var emitted = 0

    public init(maxLength: Int = 300, firstMaxLength: Int? = nil) {
        self.maxLength = maxLength
        self.firstMaxLength = firstMaxLength
    }

    public mutating func feed(_ piece: String) -> [String] {
        pending += piece
        return drain(final: false)
    }

    /// The end of the stream: whatever remains is the last sentence.
    public mutating func finish() -> [String] {
        drain(final: true)
    }

    public static func split(_ text: String, maxLength: Int = 300, firstMaxLength: Int? = nil) -> [String] {
        var splitter = SentenceSplitter(maxLength: maxLength, firstMaxLength: firstMaxLength)
        return splitter.feed(text) + splitter.finish()
    }

    static let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？", "।", "؟"]
    /// Ends that need no space after them (Japanese and Chinese run sentences together).
    static let unspacedTerminators: Set<Character> = ["。", "！", "？"]
    static let closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]"]
    /// Words that take a period without ending a sentence.
    static let abbreviations: Set<String> = [
        "M", "MM", "Mme", "Mmes", "Mlle", "Mr", "Mrs", "Ms", "Dr", "Pr", "Prof", "Me", "St", "Ste",
        "Sr", "Jr", "vs", "cf", "p", "pp", "env", "approx", "ex", "fig", "Fig", "No", "no", "vol", "chap",
    ]

    private mutating func drain(final: Bool) -> [String] {
        var out: [String] = []
        var rest = pending[...]
        scanning: while !rest.isEmpty {
            let limit = (emitted == 0 ? firstMaxLength : nil) ?? maxLength
            switch Self.scan(rest, limit: limit, final: final) {
            case .end(let end):
                append(rest[..<end], to: &out)
                rest = rest[end...]
            case .cut(let limitIndex):
                let cut = Self.cutPoint(in: rest, at: limitIndex, limit: limit)
                append(rest[..<cut], to: &out)
                rest = rest[cut...]
            case .wait:
                break scanning
            }
        }
        if final {
            append(rest, to: &out)
            rest = rest[rest.endIndex...]
        }
        pending = String(rest)
        return out
    }

    private mutating func append(_ sentence: Substring, to out: inout [String]) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        out.append(trimmed)
        emitted += 1
    }

    enum Scan: Equatable {
        /// A sentence ends just before this index.
        case end(Substring.Index)
        /// No end within the limit: cut near this index (the limit).
        case cut(Substring.Index)
        /// The answer depends on text that has not arrived yet.
        case wait
    }

    /// One pass over the next sentence, never further than `limit` characters (plus closers
    /// after a mark), so a megabyte splits in linear time.
    static func scan(_ text: Substring, limit: Int, final: Bool) -> Scan {
        var i = text.startIndex
        var count = 0
        func step() {
            i = text.index(after: i)
            count += 1
        }
        while i < text.endIndex {
            if count >= limit { return .cut(i) }
            let c = text[i]
            if c == "\n" {
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "\n" { return .end(text.index(after: next)) }
                if next == text.endIndex, !final { return .wait }
            }
            guard terminators.contains(c) else {
                step()
                continue
            }
            let mark = i
            step()
            while i < text.endIndex, terminators.contains(text[i]) || closers.contains(text[i]) { step() }
            if unspacedTerminators.contains(c) { return .end(i) }
            // A space may separate French punctuation and closers: "oui. »"
            while i < text.endIndex, text[i] == " " || text[i] == "\u{00A0}" {
                let after = text.index(after: i)
                guard after < text.endIndex, closers.contains(text[after]) else { break }
                step()
                step()
            }
            guard i < text.endIndex else { return final ? .end(i) : .wait }
            guard text[i].isWhitespace else { continue }
            if c == "." || c == "…" {
                switch continues(text, mark: mark, after: i) {
                case .some(true): continue
                case .none: return final ? .end(i) : .wait
                case .some(false): return .end(i)
                }
            }
            return .end(i)
        }
        return final ? .end(i) : .wait
    }

    /// Whether the sentence goes on after a period or an ellipsis: an abbreviation, an
    /// initial, or a lowercase word next. `nil` when the next word has not arrived.
    static func continues(_ text: Substring, mark: Substring.Index, after end: Substring.Index) -> Bool? {
        guard let next = text[end...].firstIndex(where: { !$0.isWhitespace }) else { return nil }
        if text[next].isLowercase { return true }
        guard text[mark] == "." else { return false }
        var start = mark
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous].isWhitespace { break }
            start = previous
        }
        let word = String(text[start..<mark])
        if abbreviations.contains(word) || word.contains(".") { return true }
        if word.count == 1, word.first?.isUppercase == true { return true }
        return false
    }

    /// Where to cut a run longer than the limit: after a comma, semicolon or colon, else a
    /// space, else at the limit itself (Japanese has no spaces).
    static func cutPoint(in text: Substring, at limitIndex: Substring.Index, limit: Int) -> Substring.Index {
        let head = text[..<limitIndex]
        let minimum = limit / 3
        for marks in [[",", ";", ":"], [" "]] as [[Character]] {
            if let index = head.lastIndex(where: { marks.contains($0) }),
               head.distance(from: head.startIndex, to: index) >= minimum {
                return text.index(after: index)
            }
        }
        return limitIndex
    }
}
