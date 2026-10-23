import Foundation

public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var projectID: UUID?
    public var remindAt: Date?
}

/// Parses "Call Ana #sprint tomorrow 9am" (spec §7). English date phrases are the supported set.
public enum QuickAdd {
    public static func parse(_ input: String, projects: [Project], calendar: Calendar = .current) -> QuickAddResult? {
        var text = input
        var projectID: UUID?
        if let r = text.range(of: #"#\S+"#, options: .regularExpression),
           let p = matchProject(String(text[r].dropFirst()), in: projects) {
            projectID = p.id
            text.replaceSubrange(r, with: " ")
        }
        var remindAt: Date?
        if let found = findDate(in: text, calendar: calendar) {
            let (date, r) = found
            remindAt = date
            text = dropTrailingPreposition(String(text[..<r.lowerBound])) + " " + text[r.upperBound...]
        }
        let title = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : QuickAddResult(title: title, projectID: projectID, remindAt: remindAt)
    }

    /// A date phrase on its own, for `metodo --due`: anything the Add field understands ("tomorrow 9am",
    /// "friday", "in 2 hours"), or "2026-10-23", "2026-10-23 14:30", full ISO 8601. nil unless the whole
    /// phrase is a date, so a typo errors instead of silently dropping words.
    public static func date(from phrase: String, calendar: Calendar = .current) -> Date? {
        let trimmed = phrase.trimmingCharacters(in: .whitespaces)
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = format
            if let d = f.date(from: trimmed) {
                return format.count > 10 ? d : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: d)
            }
        }
        guard let found = findDate(in: trimmed, calendar: calendar) else { return nil }
        let (date, r) = found
        let rest = String(trimmed[..<r.lowerBound]) + " " + trimmed[r.upperBound...]
        let filler: Set<String> = ["at", "on", "by"]
        return rest.split(whereSeparator: \.isWhitespace).allSatisfy { filler.contains($0.lowercased()) } ? date : nil
    }

    /// "90", "90m", "45 min", "2h", "1.5h", "1h30m", "1h 30m", "1:30" → minutes. nil for anything else.
    public static func minutes(from phrase: String) -> Int? {
        let text = phrase.trimmingCharacters(in: .whitespaces)
        let range = NSRange(text.startIndex..., in: text)
        if let m = clock.firstMatch(in: text, range: range),
           let h = Int(text[Range(m.range(at: 1), in: text)!]), let min = Int(text[Range(m.range(at: 2), in: text)!]) {
            return h * 60 + min
        }
        guard let m = duration.firstMatch(in: text, range: range) else { return nil }
        let group = { (i: Int) in Range(m.range(at: i), in: text).map { String(text[$0]) } }
        let hours = group(1).flatMap(Double.init)
        let mins = group(2).flatMap(Int.init) ?? group(3).flatMap(Int.init)
        guard hours != nil || mins != nil else { return nil }
        return Int(((hours ?? 0) * 60).rounded()) + (mins ?? 0)
    }

    static let clock = try! NSRegularExpression(pattern: #"^(\d+):([0-5]\d)$"#)
    static let duration = try! NSRegularExpression(
        pattern: #"(?i)^(?:(\d+(?:\.\d+)?)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?)?$|^(\d+)$"#)

    /// The first date phrase in `text` and where it is. No time given means 9:00.
    static func findDate(in text: String, calendar: Calendar) -> (Date, Range<String.Index>)? {
        guard let found = detectRelative(in: text, calendar: calendar) ?? detectDate(in: text) else { return nil }
        let (date, r) = found
        let phrase = String(text[r])
        guard var d = hasTime(phrase) ? date : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) else { return nil }
        // "Call mom 5pm" typed at 6 PM means tomorrow, not "already overdue".
        if d < Date(), phrase.range(of: timeOnly, options: .regularExpression) != nil {
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return (d, r)
    }

    /// Exact normalized name wins; otherwise a prefix that matches exactly one project.
    public static func matchProject(_ token: String, in projects: [Project]) -> Project? {
        let t = normalize(token)
        guard !t.isEmpty else { return nil }
        if let exact = projects.first(where: { normalize($0.name) == t }) { return exact }
        let prefixed = projects.filter { normalize($0.name).hasPrefix(t) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    /// Lowercase, accents removed, only letters and digits: "🎓 Inglés B1" → "inglesb1".
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// A detector match only counts if it contains a real date/time word, so bare numbers in
    /// titles ("entrega el 14", "sprint 42") never turn into reminders.
    /// Whole English words only, so Spanish "octubre 14" stays part of the title.
    static let dateWords = #"(?i)\b(today|tonight|tomorrow|yesterday|next|this|mon(day)?|tue(s|sday)?|wed(nesday)?|thu(rs?|rsday)?|fri(day)?|sat(urday)?|sun(day)?|jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(t|tember)?|oct(ober)?|nov(ember)?|dec(ember)?|noon|midnight|morning|afternoon|evening)\b|\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d"#

    static let timeWords = #"(?i)\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|noon|midnight|morning|afternoon|evening|tonight|\bin\s+\d+\s*(m|h)|\bat\s+\d{1,2}\b"#

    /// A phrase that is only a time of day ("5pm", "at 12:01am", "noon"), with no day in it.
    static let timeOnly = #"(?i)^\s*(at\s+)?(\d{1,2}(:\d\d)?\s*(am|pm|a\.m\.|p\.m\.)?|noon|midnight)\s*$"#

    static let relative = try! NSRegularExpression(pattern: #"(?i)\bin\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w)\b"#)

    /// NSDataDetector doesn't understand "in 2 hours", so relative offsets are parsed here.
    static func detectRelative(in text: String, calendar: Calendar) -> (Date, Range<String.Index>)? {
        guard let m = relative.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text),
              let nRange = Range(m.range(at: 1), in: text), let n = Int(text[nRange]),
              let unitRange = Range(m.range(at: 2), in: text) else { return nil }
        let component: Calendar.Component = switch text[unitRange].lowercased().first {
        case "m": .minute
        case "h": .hour
        case "d": .day
        default: .weekOfYear
        }
        guard let date = calendar.date(byAdding: component, value: n, to: Date()) else { return nil }
        return (date, r)
    }

    static func detectDate(in text: String) -> (Date, Range<String.Index>)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let date = m.date, let r = Range(m.range, in: text) else { continue }
            if text[r].range(of: dateWords, options: .regularExpression) != nil { return (date, r) }
        }
        return nil
    }

    static func hasTime(_ phrase: String) -> Bool {
        phrase.range(of: timeWords, options: .regularExpression) != nil
    }

    /// "Call Ana at" → "Call Ana" once the date after it has been removed.
    static func dropTrailingPreposition(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        for p in [" at", " on", " by"] where trimmed.lowercased().hasSuffix(p) {
            return String(trimmed.dropLast(p.count))
        }
        return trimmed
    }
}
