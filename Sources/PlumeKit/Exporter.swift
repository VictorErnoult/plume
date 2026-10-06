import Foundation

/// Formats a transcript can be exported to.
public enum ExportFormat: String, CaseIterable, Sendable, Identifiable {
    case markdown = "md"
    case text = "txt"
    case subtitles = "srt"
    case webSubtitles = "vtt"
    case json = "json"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .text: return tr("Plain text")
        case .subtitles: return tr("SRT subtitles")
        case .webSubtitles: return tr("WebVTT subtitles")
        case .json: return "JSON"
        }
    }

    /// Subtitles only make sense with timestamped speaker turns.
    public var needsSegments: Bool { self == .subtitles || self == .webSubtitles }
}

public enum Exporter {
    public static func render(_ t: Transcript, as format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return TranscriptStore.markdown(for: t)
        case .text:
            var parts: [String] = [TranscriptStore.title(for: t), ""]
            if let summary = t.summary, !summary.isEmpty { parts += [summary, ""] }
            parts.append(t.speakers.count > 1 ? TranscriptBuilder.text(for: t.segments) : t.text)
            return parts.joined(separator: "\n") + "\n"
        case .subtitles:
            return cues(for: t).enumerated().map { index, cue in
                "\(index + 1)\n\(stamp(cue.start, decimal: ",")) --> \(stamp(cue.end, decimal: ","))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .webSubtitles:
            let body = cues(for: t).map { cue in
                "\(stamp(cue.start, decimal: ".")) --> \(stamp(cue.end, decimal: "."))\n\(cue.text)\n"
            }.joined(separator: "\n")
            return "WEBVTT\n\n" + body
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return (try? encoder.encode(t)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
    }

    /// Suggested file name: `2026-10-02_14-31-05 Point lancement.srt`.
    public static func fileName(for t: Transcript, format: ExportFormat) -> String {
        var name = t.id
        if let title = t.title, !title.isEmpty {
            let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|")).joined(separator: " ")
            name += " " + safe.prefix(60)
        }
        return "\(name).\(format.rawValue)"
    }

    struct Cue: Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    /// A subtitle cue never exceeds two lines: long speaker turns are
    /// split into chunks, whose duration is shared out in proportion to the words.
    static let maxCueCharacters = 84

    static func cues(for t: Transcript) -> [Cue] {
        let segments = t.segments.isEmpty
            ? [Segment(id: 0, speaker: "", channel: .mic, start: 0, end: t.duration, text: t.text)]
            : t.segments
        var cues: [Cue] = []
        for segment in segments {
            let pieces = split(segment.text, limit: maxCueCharacters)
            guard !pieces.isEmpty else { continue }
            let words = pieces.map { Double(max(1, $0.split(separator: " ").count)) }
            let total = words.reduce(0, +)
            var clock = segment.start
            let length = max(0.5, segment.end - segment.start)
            for (piece, count) in zip(pieces, words) {
                let share = length * count / total
                let name = t.speakers.count > 1 && !segment.speaker.isEmpty ? "\(segment.speaker) : " : ""
                cues.append(Cue(start: clock, end: clock + share, text: name + piece))
                clock += share
            }
        }
        return cues
    }

    /// Splits a text into chunks of at most `limit` characters, at spaces.
    static func split(_ text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                pieces.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// `00:01:05,250` (SRT) or `00:01:05.250` (WebVTT).
    static func stamp(_ seconds: Double, decimal: String) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let ms = Int((total - Double(Int(total))) * 1000)
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, decimal, ms)
    }
}
