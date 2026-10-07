import Foundation

/// Usage figures computed from the library, for the home page.
public struct LibraryStats: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var date: Date
        public var words: Int
        public var id: Date { date }
    }

    public var transcripts = 0
    public var dictations = 0
    public var meetings = 0
    public var words = 0
    /// Total audio duration, in seconds.
    public var duration: Double = 0
    public var wordsThisWeek = 0
    /// Average speed in dictation, in words per minute.
    public var wordsPerMinute = 0
    /// Time saved compared with typing on the keyboard, in seconds.
    public var timeSaved: Double = 0
    /// Consecutive days of use, today or yesterday included.
    public var streak = 0
    /// Longest streak ever reached.
    public var bestStreak = 0
    /// Words dictated today.
    public var wordsToday = 0
    /// Best day: the most words dictated in one day.
    public var bestDay: Day?
    /// Words per day over the last days, from oldest to newest.
    public var days: [Day] = []

    /// Reference typing speed used to estimate the time saved.
    public static let typingWordsPerMinute = 40.0

    public init() {}

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }

    public init(transcripts list: [Transcript], now: Date = Date(), dayCount: Int = 371, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var perDay: [Date: Int] = [:]
        var dictatedWords = 0
        var dictatedSeconds = 0.0

        for t in list {
            // For a meeting, only what the owner said counts as "dictated".
            let spoken: Int
            if t.speakers.count > 1 {
                spoken = t.segments.filter { TranscriptBuilder.isMe($0.speaker) }.reduce(0) { $0 + Self.wordCount($1.text) }
            } else {
                spoken = Self.wordCount(t.text)
            }
            transcripts += 1
            if t.mode == .dictation { dictations += 1 }
            if t.mode == .meeting { meetings += 1 }
            words += spoken
            duration += t.duration
            let day = calendar.startOfDay(for: t.createdAt)
            perDay[day, default: 0] += spoken
            if day >= weekStart { wordsThisWeek += spoken }
            if t.mode == .dictation {
                dictatedWords += spoken
                dictatedSeconds += t.duration
            }
        }

        if dictatedSeconds > 0 {
            wordsPerMinute = Int((Double(dictatedWords) / (dictatedSeconds / 60)).rounded())
        }
        timeSaved = max(0, Double(dictatedWords) / Self.typingWordsPerMinute * 60 - dictatedSeconds)

        days = (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: date, words: perDay[date] ?? 0)
        }

        wordsToday = perDay[today] ?? 0
        if let best = perDay.max(by: { $0.value < $1.value }), best.value > 0 {
            bestDay = Day(date: best.key, words: best.value)
        }
        // Longest run of consecutive days across the whole history.
        var run = 0
        var previous: Date?
        for day in perDay.keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            bestStreak = max(bestStreak, run)
            previous = day
        }

        // The streak stays alive if nothing has been dictated yet today.
        var cursor = today
        if perDay[cursor] == nil, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            cursor = yesterday
        }
        while perDay[cursor] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
    }
}
