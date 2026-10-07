import Foundation

/// Interface language. The code is written in English; French comes from a translation
/// table. English is the app's default language. The other language is picked in the
/// settings, regardless of the system's.
public enum Language: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case french = "fr"

    public var id: String { rawValue }

    /// The language's name, in the language itself.
    public var label: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        }
    }

    /// For dates and numbers.
    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .french: return Locale(identifier: "fr_FR")
        }
    }
}

public enum L10n {
    /// Current language. The sources are in English: it is the default, also used by tests;
    /// the app and the command line set it at launch from the settings.
    public static var current: Language {
        get { override ?? stored }
        set { stored = newValue }
    }

    nonisolated(unsafe) private static var stored: Language = .english

    /// A language for the length of a block, for the current task only: tests use it
    /// instead of changing `current`, which other tests read at the same time.
    @TaskLocal public static var override: Language?

    /// Translation of an English string. A string missing from the table comes back as is.
    public static func translate(_ english: String) -> String {
        guard current == .french else { return english }
        return french[english] ?? english
    }

    /// Table entries without a translation (diagnostics).
    public static var missing: [String] { french.filter { $0.value.isEmpty }.map(\.key).sorted() }

    /// English → French, for everything the interface shows.
    static let french: [String: String] = L10nTable.french
}

/// `tr("History")`: the text in the current language.
public func tr(_ english: String) -> String {
    L10n.translate(english)
}
