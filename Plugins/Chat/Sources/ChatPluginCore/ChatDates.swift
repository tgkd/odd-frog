import Foundation

public struct ChatDates: Sendable {
    public struct Parsed: Sendable, Equatable {
        public var date: Date
        public var hasTime: Bool
    }

    private let now: Date
    private let calendar: Calendar

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    public func parse(_ text: String) -> Parsed? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (pattern, hasTime) in [("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm", true),
                                   ("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd", false)] {
            if let date = formatter(pattern).date(from: value) {
                return Parsed(date: date, hasTime: hasTime)
            }
        }
        return nil
    }

    public var today: String {
        formatter("yyyy-MM-dd").string(from: now)
    }

    public func combine(date: String, time: String?) -> Parsed? {
        let day = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clock = time?.trimmingCharacters(in: .whitespacesAndNewlines), !clock.isEmpty else {
            return parse(day)
        }
        guard let base = parse(day), let minutes = Self.minutes(of: clock) else {
            return nil
        }
        let midnight = calendar.startOfDay(for: base.date)
        guard let value = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight) else {
            return nil
        }
        return Parsed(date: value, hasTime: true)
    }

    public static func minutes(of clock: String) -> Int? {
        let text = clock.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
        let suffix = text.hasSuffix("am") ? "am" : text.hasSuffix("pm") ? "pm" : ""
        let digits = String(text.dropLast(suffix.count))
        let parts = digits.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]),
              let minute = parts.count == 2 ? Int(parts[1]) : 0, (0..<60).contains(minute) else {
            return nil
        }
        switch suffix {
        case "am", "pm":
            guard (1...12).contains(hour) else { return nil }
            return ((hour % 12) + (suffix == "pm" ? 12 : 0)) * 60 + minute
        default:
            guard (0..<24).contains(hour) else { return nil }
            return hour * 60 + minute
        }
    }

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86400)
    }

    public func describe(_ date: Date, time: Bool) -> String {
        formatter(time ? "EEE yyyy-MM-dd HH:mm" : "EEE yyyy-MM-dd").string(from: date)
    }

    public func clock(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    public func describeNow() -> String {
        formatter("EEEE yyyy-MM-dd HH:mm").string(from: now) + " (\(calendar.timeZone.identifier))"
    }

    private func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        formatter.isLenient = false
        return formatter
    }
}
