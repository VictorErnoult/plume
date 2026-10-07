import Foundation

/// Commands dictated aloud: "à la ligne" (new line), "nouveau paragraphe" (new paragraph),
/// "point d'interrogation" (question mark), "efface ça" (delete that), "appuie sur Entrée"
/// (press Return)… The model writes them as ordinary words, most often surrounded by punctuation
/// ("Bonjour, à la ligne, je voulais…"): they are found here afterwards to be executed. In French and English.
public enum VoiceCommands {
    public struct Result: Sendable, Equatable {
        public var text: String
        /// The dictation ended with "appuie sur Entrée" (press Return): submit once the text is pasted.
        public var pressReturn: Bool

        public init(text: String, pressReturn: Bool = false) {
            self.text = text
            self.pressReturn = pressReturn
        }
    }

    public static func apply(to text: String) -> Result {
        var result = text
        var pressReturn = false
        if let range = sendCommand.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)).flatMap({ Range($0.range, in: result) }) {
            result.removeSubrange(range)
            pressReturn = true
        }
        for (regex, template) in rewrites {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        result = scratched(result)
        return Result(text: tidy(result), pressReturn: pressReturn)
    }

    // MARK: - The commands

    /// Spaces and punctuation the model sticks before or after a command.
    private static let before = "[ \\t]*"
    private static let after = "[ \\t]*[.,;:]*[ \\t]*"
    /// The command is a sentence on its own: preceded by punctuation or the start of the text.
    private static let isolatedBefore = "(?:^|(?<=[.!?…,;\\n]))[ \\t]*"
    private static let isolatedAfter = "[ \\t]*(?=[.!?…,;\\n]|$)[.!?…,;]*[ \\t]*"

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// "Appuie sur Entrée" (press Return) at the very end: the message sends as soon as it is pasted.
    private static let sendCommand = regex(
        "[ \\t]*[,;]?[ \\t]*\\b(?:appu(?:ie|ies|ya|yer|yez) sur (?:la touche )?entr(?:ée|ee|er|ez)|press enter|hit enter)\\b[ \\t.!,]*$")!

    /// Rewrites in order: dictated punctuation and quotes, then line breaks, then bullets.
    private static let rewrites: [(NSRegularExpression, String)] = [
        // Punctuation spoken explicitly (the model already punctuates by itself, so we only keep what
        // can't be an ordinary word). French style: a space before ? ! : ;
        ("\(before)[,.;]?\(before)\\bpoint d['’]interrogation\\b\(after)", " ? "),
        ("\(before)[,.;]?\(before)\\bpoint d['’]exclamation\\b\(after)", " ! "),
        ("\(before)[,.;]?\(before)\\bpoints? de suspension\\b\(after)", "… "),
        ("\(before)[,.;]?\(before)\\bpoint[ -]virgule\\b\(after)", " ; "),
        // "Deux points" (colon) is a command only if followed by a pause (punctuation) or the end.
        ("\(before)[,.;]?\(before)\\b(?:deux|2)[ -]points\\b(?=[ \\t]*(?:[,.;:\\n]|$))\(after)", " : "),
        ("\(before)[,.;]?\(before)\\bquestion mark\\b\(after)", "? "),
        ("\(before)[,.;]?\(before)\\bexclamation (?:mark|point)\\b\(after)", "! "),
        // Quotes and parentheses. After a closing one, punctuation stays: « oui ».
        ("\(before)\\bouvr(?:ez|e|ir) (?:les?|des) guillemets?\\b\(after)", " « "),
        ("\(before)[,.;]?\(before)\\bferm(?:ez|e|er) (?:les?|des) guillemets?\\b[ \\t]*", " »"),
        ("\(before)\\bopen quotes?\\b\(after)", " \""),
        ("\(before)[,.;]?\(before)\\b(?:close quotes?|end quotes?|unquote)\\b[ \\t]*", "\""),
        ("\(before)\\bouvr(?:ez|e|ir) (?:la |une )?parenth[èe]se\\b\(after)", " ("),
        ("\(before)[,.;]?\(before)\\bferm(?:ez|e|er) (?:la )?parenth[èe]se\\b[ \\t]*", ")"),
        ("\(before)\\bopen paren(?:thesis)?\\b\(after)", " ("),
        ("\(before)[,.;]?\(before)\\bclose paren(?:thesis)?\\b[ \\t]*", ")"),
        // Breaks. "Un nouveau paragraphe", "la nouvelle ligne de produits", "pêche à la ligne"
        // or "à la ligne 12" are not commands.
        ("\(before)\\bpoint à la ligne\\b(?!\\s*\\d)\(after)", ".\n"),
        ("\(before)(?<!\\b(?:le|un|ce|du|au|chaque|premier|dernier|a|the|this|each|first|last) )\\b(?:nouveau paragraphe|new paragraph)\\b\(after)", "\n\n"),
        (
            "\(before)(?<!\\b(?:la|une|cette|notre|votre|leur|sa|ma|ta|de|the|a|this|each|next|one) )(?<!\\bpêch(?:e|er|ent|es|ez|ait|ant) )"
                + "\\b(?:retour à la ligne|(?:aller |va |passe |passer )?à la ligne|nouvelle ligne|new ?line)\\b"
                + "(?![ \\t]*(?:\\d|(?:suivante|précédente|près|d['’e]|du|des|below|above)\\b))\(after)", "\n"
        ),
        // Bullets: "nouvelle puce" (new bullet), or "tiret" (dash) right after a line break.
        ("\(before)\\b(?:nouvelle puce|bullet point|new bullet)\\b\(after)", "\n- "),
        ("\\n[ \\t]*\\btiret\\b[ \\t]*[,.;:]?[ \\t]*", "\n- "),
    ].compactMap { (pattern: String, template: String) -> (NSRegularExpression, String)? in
        regex(pattern).map { ($0, template) }
    }

    /// "Efface ça" (delete that) removes the preceding sentence; "efface tout" (delete all) removes everything before.
    private static let scratchCommand = regex(
        "\(isolatedBefore)\\b(?:(efface(?:r|z)? tout|annule(?:r|z)? tout|tout effacer|delete everything|clear everything)"
            + "|efface(?:r|z)? (?:ça|cela|ca)|supprime(?:r|z)? (?:ça|cela)|annule(?:r|z)? (?:ça|cela)|scratch that|delete that)\\b\(isolatedAfter)")!

    private static func scratched(_ text: String) -> String {
        var result = text
        while let match = scratchCommand.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
            let range = Range(match.range, in: result)
        {
            let everything = match.range(at: 1).location != NSNotFound
            var kept = String(result[..<range.lowerBound])
            if everything {
                kept = ""
            } else {
                // The punctuation of the sentence to delete, then the sentence itself, up to the end
                // of the one before.
                while let last = kept.last, " .!?…".contains(last) { kept.removeLast() }
                if let boundary = kept.lastIndex(where: { ".!?…\n".contains($0) }) {
                    kept = String(kept[...boundary])
                } else {
                    kept = ""
                }
            }
            var rest = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = capitalizingFirst(rest)
            if !kept.isEmpty, !rest.isEmpty, kept.last != "\n" { kept += " " }
            result = kept + rest
        }
        return result
    }

    // MARK: - Tidy-up

    private static let tidyRules: [(NSRegularExpression, String)] = [
        ("[ \\t]+\\n", "\n"),
        ("\\n[ \\t]+", "\n"),
        ("\\n{3,}", "\n\n"),
        ("[ \\t]{2,}", " "),
        // No space before a comma or a period (the semicolon keeps one, French style).
        ("[ \\t]+([,.])", "$1"),
        ("([,;:])[,;:]+", "$1"),
        ("\\.{2}(?!\\.)", "."),
        // Nothing precedes punctuation at the start of a line, except a bullet.
        ("(^|\\n)[,.;:]+[ \\t]*", "$1"),
        ("« {2,}", "« "),
        (" {2,}»", " »"),
        // An orphan comma at the end of the text ("à bientôt, appuie sur Entrée"), or before a bullet.
        ("[ \\t]*[,;]+[ \\t]*$", ""),
        ("[,;]+\\n(- )", "\n$1"),
    ].compactMap { (pattern: String, template: String) -> (NSRegularExpression, String)? in
        regex(pattern).map { ($0, template) }
    }

    private static func tidy(_ text: String) -> String {
        var result = text
        for (regex, template) in tidyRules {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        // A capital after each line break (except on a bullet, which keeps the dictated case).
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        result = lines.enumerated().map { index, line in
            index == 0 || line.hasPrefix("- ") ? line : capitalizingFirst(line)
        }.joined(separator: "\n")
        // Edge spaces go; a dictated final line break stays.
        while let first = result.first, first == " " || first == "\t" { result.removeFirst() }
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        return result.allSatisfy(\.isWhitespace) ? "" : result
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter }), text[index].isLowercase,
            text[..<index].allSatisfy({ " «\"(".contains($0) })
        else { return text }
        return String(text[..<index]) + text[index].uppercased() + String(text[text.index(after: index)...])
    }
}
