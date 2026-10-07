import Foundation

/// What surrounds the cursor in the active field, a few characters on each side.
public struct InsertionContext: Sendable, Equatable {
    public var before: String
    public var after: String

    public init(before: String, after: String = "") {
        self.before = before
        self.after = after
    }

    public static let empty = InsertionContext(before: "")
}

/// Adapts a dictation to where it is pasted: a space if the cursor touches a
/// word, a lowercase letter if the sentence is already started, no final period if it continues.
/// The model writes each dictation as a complete text; here we blend it into what exists.
public enum SmartInsert {
    public static func adapt(_ text: String, context: InsertionContext) -> String {
        guard !text.isEmpty else { return text }
        let before = context.before
        let after = context.after
        var result = text

        // Last visible character before the cursor; nothing, or a line break: start of text.
        let previous = before.last(where: { $0 != " " && $0 != "\t" && $0 != "\u{A0}" })
        guard let previous, previous != "\n", previous != "\r" else { return result }
        let next = after.first(where: { $0 != " " && $0 != "\t" && $0 != "\u{A0}" })

        // The current sentence is not finished: continue it in lowercase.
        let midSentence = previous.isLetter || previous.isNumber || ",;:)]}»\"'".contains(previous)
        if midSentence, let first = result.first, first.isUppercase, startsWithCommonWord(result) {
            result = first.lowercased() + result.dropFirst()
        }
        // And no final period if it continues after the cursor, on the same line.
        let continues = next.map { $0.isLetter || $0.isNumber || ",;".contains($0) } ?? false
        let sameLine = !after.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("\n")
        if continues, sameLine, result.hasSuffix("."), !result.hasSuffix("..") { result.removeLast() }

        // A space between the previous word and the dictation; none after an opening character.
        if let last = before.last, !last.isWhitespace, !"([{«\"'‘“/".contains(last), !result.hasPrefix("\n") {
            result = " " + result
        }
        // And one after, if the text resumes right away.
        if let first = after.first, first.isLetter || first.isNumber || "([«".contains(first), !result.hasSuffix("\n") {
            result += " "
        }
        return result
    }

    /// Common words that open a sentence: these lose their capital safely,
    /// unlike a proper noun ("Paris") that we can't recognize.
    private static let commonWords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "au", "aux", "et", "ou", "mais", "donc", "or",
        "ni", "car", "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ce", "c", "ça", "cela",
        "ceci", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos",
        "votre", "vos", "leur", "leurs", "que", "qu", "qui", "quoi", "dont", "où", "quand", "comme", "si", "pour",
        "par", "sur", "sous", "dans", "avec", "sans", "chez", "vers", "entre", "en", "à", "y", "ne", "n", "pas",
        "plus", "moins", "très", "trop", "bien", "mal", "aussi", "alors", "puis", "ensuite", "enfin", "encore",
        "déjà", "toujours", "jamais", "peut", "peut-être", "est", "sont", "a", "ai", "as", "avons", "avez", "ont",
        "été", "être", "avoir", "faire", "fait", "faut", "va", "vais", "vas", "vont", "voilà", "voici", "merci",
        "oui", "non", "bon", "bonne", "tout", "tous", "toute", "toutes", "rien", "chaque", "quelque", "quelques",
        "après", "avant", "depuis", "pendant", "parce", "lorsque", "comment", "pourquoi", "combien", "ici", "là",
        "the", "a", "an", "and", "or", "but", "so", "if", "it", "its", "it's", "he", "she", "we", "they", "you",
        "this", "that", "these", "those", "my", "your", "our", "their", "his", "her", "to", "of", "in", "on", "at",
        "for", "with", "from", "by", "as", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do",
        "does", "did", "not", "no", "yes", "then", "also", "just", "very", "more", "less", "can", "could", "will",
        "would", "should", "there", "here", "when", "where", "what", "which", "who", "how", "why", "because",
        "please", "thanks", "ok", "okay", "let's", "let", "all", "some", "any", "every", "about", "into", "over",
    ]

    private static func startsWithCommonWord(_ text: String) -> Bool {
        let end = text.firstIndex(where: { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" }) ?? text.endIndex
        var word = String(text[..<end]).lowercased().replacingOccurrences(of: "’", with: "'")
        // "J'ai": it is the elided pronoun that counts.
        if let apostrophe = word.firstIndex(of: "'") { word = String(word[..<apostrophe]) }
        return commonWords.contains(word)
    }
}
