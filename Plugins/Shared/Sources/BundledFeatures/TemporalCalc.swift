import Foundation

public struct CivilDate: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }
}

public struct TemporalCalculation: Sendable, Hashable {
    public enum Value: Sendable, Hashable {
        case instant(Date, TimeZone)
        case civilDate(CivilDate)
        case civilDayDifference(Int)
        case elapsed(TimeInterval)
    }

    public let input: String
    public let value: Value
    public let title: String
    public let subtitle: String
    public let copyText: String

    public var kindLabel: String {
        switch value {
        case .instant, .elapsed: "Time"
        case .civilDate, .civilDayDifference: "Date"
        }
    }
}

public enum TemporalCalc {
    public enum Recognition: Sendable, Hashable {
        case notTemporal
        case rejected
        case value(TemporalCalculation)
    }

    public static func recognize(_ text: String, now: Date, timeZone: TimeZone, locale: Locale) -> Recognition {
        let input = text.trimmingCharacters(in: .whitespaces)
        let characters = Array(input.lowercased())
        let fallback: Recognition = containsISODate(characters) ? .rejected : .notTemporal
        guard let lexemes = tokenize(characters) else { return fallback }
        var parser = Parser(lexemes: lexemes)
        guard let expression = try? parser.parse(), expression.isExplicit else { return fallback }
        let evaluator = Evaluator(
            now: Date(timeIntervalSince1970: floor(now.timeIntervalSince1970)),
            local: TimeZoneResolver.named(timeZone),
            locale: locale
        )
        guard let calculation = try? evaluator.evaluate(expression, input: input) else { return fallback }
        return .value(calculation)
    }

    enum Token: Equatable {
        case number(String)
        case clock(hour: Int, minute: Int, second: Int?)
        case isoDate(CivilDate)
        case word(String)
        case plus
        case minus
        case arrow
    }

    struct Lexeme: Equatable {
        let token: Token
        let spaced: Bool
    }

    static func tokenize(_ characters: [Character]) -> [Lexeme]? {
        var lexemes: [Lexeme] = []
        var index = 0
        var spaced = true
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace || character == "," {
                spaced = true
                index += 1
                continue
            }
            let token: Token
            if let match = isoDate(characters, at: index) {
                token = .isoDate(match.date)
                index = match.end
            } else if isDigit(character) {
                guard let match = numeric(characters, at: index) else { return nil }
                token = match.token
                index = match.end
            } else if character.isLetter {
                var end = index
                while end < characters.count, isWordCharacter(characters, at: end) {
                    end += 1
                }
                token = .word(String(characters[index..<end]))
                index = end
            } else {
                switch character {
                case "+": token = .plus
                case "−": token = .minus
                case "→": token = .arrow
                case "-" where index + 1 < characters.count && characters[index + 1] == ">":
                    token = .arrow
                    index += 1
                case "-": token = .minus
                default: return nil
                }
                index += 1
            }
            lexemes.append(Lexeme(token: token, spaced: spaced))
            spaced = false
        }
        return lexemes
    }

    static func containsISODate(_ characters: [Character]) -> Bool {
        characters.indices.contains { index in
            guard isDigit(characters[index]) else { return false }
            if index > 0 {
                let previous = characters[index - 1]
                if isDigit(previous) || previous.isLetter || previous == "." || previous == "-" || previous == ":" {
                    return false
                }
            }
            return isoDate(characters, at: index) != nil
        }
    }

    private static func isoDate(_ characters: [Character], at start: Int) -> (date: CivilDate, end: Int)? {
        let yearEnd = digitRun(characters, from: start)
        guard yearEnd == start + 4, yearEnd < characters.count, characters[yearEnd] == "-" else { return nil }
        let monthEnd = digitRun(characters, from: yearEnd + 1)
        guard (1...2).contains(monthEnd - yearEnd - 1), monthEnd < characters.count, characters[monthEnd] == "-" else { return nil }
        let dayEnd = digitRun(characters, from: monthEnd + 1)
        guard (1...2).contains(dayEnd - monthEnd - 1) else { return nil }
        if dayEnd < characters.count, [".", ":", "-"].contains(characters[dayEnd]) {
            return nil
        }
        guard let year = Int(String(characters[start..<yearEnd])),
              let month = Int(String(characters[(yearEnd + 1)..<monthEnd])),
              let day = Int(String(characters[(monthEnd + 1)..<dayEnd])) else { return nil }
        return (CivilDate(year: year, month: month, day: day), dayEnd)
    }

    private static func numeric(_ characters: [Character], at start: Int) -> (token: Token, end: Int)? {
        let whole = digitRun(characters, from: start)
        if whole < characters.count, characters[whole] == ":" {
            guard whole - start <= 2, let hour = Int(String(characters[start..<whole])),
                  let minute = twoDigits(characters, at: whole + 1) else { return nil }
            var end = whole + 3
            var second: Int?
            if end < characters.count, characters[end] == ":" {
                guard let value = twoDigits(characters, at: end + 1) else { return nil }
                second = value
                end += 3
            }
            return (.clock(hour: hour, minute: minute, second: second), end)
        }
        var end = whole
        if end + 1 < characters.count, characters[end] == ".", isDigit(characters[end + 1]) {
            end = digitRun(characters, from: end + 1)
        }
        return (.number(String(characters[start..<end])), end)
    }

    private static func digitRun(_ characters: [Character], from start: Int) -> Int {
        var end = start
        while end < characters.count, isDigit(characters[end]) {
            end += 1
        }
        return end
    }

    private static func twoDigits(_ characters: [Character], at start: Int) -> Int? {
        guard digitRun(characters, from: start) == start + 2 else { return nil }
        return Int(String(characters[start..<(start + 2)]))
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func isWordCharacter(_ characters: [Character], at index: Int) -> Bool {
        let character = characters[index]
        if character.isLetter || character == "_" || character == "/" {
            return true
        }
        guard character == "-", index > 0, index + 1 < characters.count else { return false }
        return characters[index - 1].isLetter && characters[index + 1].isLetter
    }

    enum Unit {
        case elapsed(seconds: Double)
        case calendar(Calendar.Component, multiple: Int)

        init?(_ word: String) {
            switch word {
            case "s", "sec", "secs", "second", "seconds": self = .elapsed(seconds: 1)
            case "m", "min", "mins", "minute", "minutes": self = .elapsed(seconds: 60)
            case "h", "hr", "hrs", "hour", "hours": self = .elapsed(seconds: 3600)
            case "d", "day", "days": self = .calendar(.day, multiple: 1)
            case "w", "wk", "wks", "week", "weeks": self = .calendar(.day, multiple: 7)
            case "mo", "mos", "mon", "month", "months": self = .calendar(.month, multiple: 1)
            case "y", "yr", "yrs", "year", "years": self = .calendar(.year, multiple: 1)
            default: return nil
            }
        }
    }

    struct Clock: Equatable {
        let hour: Int
        let minute: Int
        let second: Int
    }

    enum Day: Equatable {
        case now
        case relative(Int)
        case calendar(year: Int?, month: Int, day: Int)
    }

    struct Anchor {
        var day: Day?
        var clock: Clock?
        var zone: ResolvedZone?
    }

    struct Shift {
        let sign: Double
        let parts: [(unit: Unit, amount: Double)]
    }

    struct Expression {
        let anchor: Anchor
        let shifts: [Shift]
        let subtrahend: Anchor?
        let conversion: ResolvedZone?

        var isExplicit: Bool {
            anchor.zone != nil || !shifts.isEmpty || subtrahend != nil || conversion != nil
        }
    }

    struct Parser {
        let lexemes: [Lexeme]
        var index = 0

        enum Failure: Error {
            case invalid
        }

        static let months: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12,
        ]

        static let meridiems: [String: Bool] = ["am": false, "pm": true]

        private var current: Token? {
            lexeme(at: 0)?.token
        }

        private func lexeme(at offset: Int) -> Lexeme? {
            let position = index + offset
            return position < lexemes.count ? lexemes[position] : nil
        }

        mutating func parse() throws -> Expression {
            let anchor = try requireAnchor()
            var shifts: [Shift] = []
            var subtrahend: Anchor?
            while subtrahend == nil, let token = current, token == .plus || token == .minus {
                index += 1
                if let parts = try duration() {
                    shifts.append(Shift(sign: token == .plus ? 1 : -1, parts: parts))
                } else if token == .minus {
                    subtrahend = try requireAnchor()
                } else {
                    throw Failure.invalid
                }
            }
            var conversion: ResolvedZone?
            if let token = current, token == .arrow || token == .word("in") || token == .word("to") || token == .word("as") {
                index += 1
                guard let zone = try zone(allowsBareOffset: false) else { throw Failure.invalid }
                conversion = zone
            }
            guard index == lexemes.count else { throw Failure.invalid }
            return Expression(anchor: anchor, shifts: shifts, subtrahend: subtrahend, conversion: conversion)
        }

        private mutating func requireAnchor() throws -> Anchor {
            guard let anchor = try anchor() else { throw Failure.invalid }
            return anchor
        }

        private mutating func anchor() throws -> Anchor? {
            var anchor = Anchor()
            if current == .word("now") {
                index += 1
                anchor.day = .now
                anchor.zone = try zone(allowsBareOffset: false)
                return anchor
            }
            var allowsBareOffset = false
            if let day = day() {
                anchor.day = day
                if case .calendar? = anchor.day, current == .word("t"), let marker = lexeme(at: 0), let next = lexeme(at: 1), !marker.spaced, !next.spaced {
                    index += 1
                    guard let clock = try clock() else { throw Failure.invalid }
                    anchor.clock = clock
                    allowsBareOffset = true
                } else if current == .word("at") {
                    index += 1
                    guard let clock = try clock() else { throw Failure.invalid }
                    anchor.clock = clock
                } else {
                    anchor.clock = try clock()
                }
            } else if let clock = try clock() {
                anchor.clock = clock
                anchor.day = day()
            } else {
                return nil
            }
            anchor.zone = try zone(allowsBareOffset: allowsBareOffset)
            return anchor
        }

        private mutating func day() -> Day? {
            switch current {
            case .isoDate(let date)?:
                index += 1
                return .calendar(year: date.year, month: date.month, day: date.day)
            case .word("today")?:
                index += 1
                return .relative(0)
            case .word("tomorrow")?:
                index += 1
                return .relative(1)
            case .word("yesterday")?:
                index += 1
                return .relative(-1)
            case .word(let word)?:
                guard let month = Self.months[word], case .number(let text)? = lexeme(at: 1)?.token, let day = Self.dayNumber(text) else { return nil }
                index += 2
                return .calendar(year: yearNumber(), month: month, day: day)
            case .number(let text)?:
                guard let day = Self.dayNumber(text), case .word(let word)? = lexeme(at: 1)?.token, let month = Self.months[word] else { return nil }
                index += 2
                return .calendar(year: yearNumber(), month: month, day: day)
            default:
                return nil
            }
        }

        private mutating func yearNumber() -> Int? {
            guard case .number(let text)? = current, text.count == 4, text.allSatisfy(\.isNumber) else { return nil }
            index += 1
            return Int(text)
        }

        private static func dayNumber(_ text: String) -> Int? {
            guard (1...2).contains(text.count), text.allSatisfy(\.isNumber) else { return nil }
            return Int(text)
        }

        private mutating func clock() throws -> Clock? {
            switch current {
            case .word("noon")?:
                index += 1
                return Clock(hour: 12, minute: 0, second: 0)
            case .word("midnight")?:
                index += 1
                return Clock(hour: 0, minute: 0, second: 0)
            case .clock(let hour, let minute, let second)?:
                index += 1
                let meridiem = meridiem()
                guard (0...59).contains(minute), (0...59).contains(second ?? 0) else { throw Failure.invalid }
                return Clock(hour: try Self.hour(hour, meridiem: meridiem), minute: minute, second: second ?? 0)
            case .number(let text)?:
                guard text.count <= 2, text.allSatisfy(\.isNumber), let hour = Int(text),
                      case .word(let word)? = lexeme(at: 1)?.token, let pm = Self.meridiems[word] else { return nil }
                index += 2
                return Clock(hour: try Self.hour(hour, meridiem: pm), minute: 0, second: 0)
            default:
                return nil
            }
        }

        private mutating func meridiem() -> Bool? {
            guard case .word(let word)? = current, let pm = Self.meridiems[word] else { return nil }
            index += 1
            return pm
        }

        private static func hour(_ hour: Int, meridiem: Bool?) throws -> Int {
            guard let meridiem else {
                guard (0...23).contains(hour) else { throw Failure.invalid }
                return hour
            }
            guard (1...12).contains(hour) else { throw Failure.invalid }
            return hour % 12 + (meridiem ? 12 : 0)
        }

        private mutating func duration() throws -> [(unit: Unit, amount: Double)]? {
            var parts: [(unit: Unit, amount: Double)] = []
            while case .number(let text)? = current, case .word(let word)? = lexeme(at: 1)?.token, let unit = Unit(word) {
                guard let amount = Double(text), amount <= 1_000_000 else { throw Failure.invalid }
                parts.append((unit, amount))
                index += 2
            }
            return parts.isEmpty ? nil : parts
        }

        private mutating func zone(allowsBareOffset: Bool) throws -> ResolvedZone? {
            if case .word(let word)? = current, word == "utc" || word == "gmt", let offset = try signedOffset(at: index + 1) {
                index += 3
                return offset
            }
            if allowsBareOffset, let offset = try signedOffset(at: index) {
                index += 2
                return offset
            }
            var words: [String] = []
            while words.count < 3, case .word(let word)? = lexeme(at: words.count)?.token {
                words.append(word)
            }
            for count in stride(from: words.count, through: 1, by: -1) {
                guard let zone = TimeZoneResolver.zone(named: words.prefix(count).joined(separator: " ")) else { continue }
                index += count
                return zone
            }
            return nil
        }

        private func signedOffset(at position: Int) throws -> ResolvedZone? {
            guard position + 1 < lexemes.count, !lexemes[position].spaced, !lexemes[position + 1].spaced else { return nil }
            let sign: Int
            switch lexemes[position].token {
            case .plus: sign = 1
            case .minus: sign = -1
            default: return nil
            }
            if position + 2 < lexemes.count, !lexemes[position + 2].spaced, case .word = lexemes[position + 2].token {
                return nil
            }
            let hours: Int
            let minutes: Int
            switch lexemes[position + 1].token {
            case .clock(let hour, let minute, nil):
                hours = hour
                minutes = minute
            case .number(let text) where text.count <= 2 && text.allSatisfy(\.isNumber):
                hours = Int(text) ?? 0
                minutes = 0
            default:
                return nil
            }
            guard let zone = TimeZoneResolver.zone(offsetSign: sign, hours: hours, minutes: minutes) else { throw Failure.invalid }
            return zone
        }
    }

    struct Evaluator {
        let now: Date
        let local: ResolvedZone
        let locale: Locale

        enum Moment {
            case instant(Date)
            case civil(CivilDate)
        }

        enum Failure: Error {
            case invalid
        }

        static let utc = gregorian(.gmt)
        static let supported = Date(timeIntervalSince1970: -62_135_596_800)..<Date(timeIntervalSince1970: 253_402_300_800)

        static func gregorian(_ timeZone: TimeZone) -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar
        }

        func evaluate(_ expression: Expression, input: String) throws -> TemporalCalculation {
            let source = expression.anchor.zone ?? local
            let calendar = Self.gregorian(source.timeZone)
            var moment = try resolve(expression.anchor)
            for shift in expression.shifts {
                moment = try apply(shift, to: moment, in: calendar)
            }
            if let subtrahend = expression.subtrahend {
                guard expression.conversion == nil else { throw Failure.invalid }
                return try difference(moment, try resolve(subtrahend), input: input)
            }
            switch moment {
            case .civil(let date):
                guard expression.conversion == nil else { throw Failure.invalid }
                return civilResult(date, input: input)
            case .instant(let date):
                return instantResult(date, source: source, output: expression.conversion ?? local, input: input)
            }
        }

        private func resolve(_ anchor: Anchor) throws -> Moment {
            let calendar = Self.gregorian((anchor.zone ?? local).timeZone)
            let today = Self.civil(now, in: calendar)
            let date: CivilDate
            switch anchor.day {
            case .now?:
                return .instant(now)
            case .relative(let offset)?:
                date = try Self.adding(offset, .day, to: today)
            case .calendar(let year, let month, let day)?:
                date = try Self.validated(CivilDate(year: year ?? today.year, month: month, day: day))
            case nil:
                date = today
            }
            guard let clock = anchor.clock else { return .civil(date) }
            return .instant(try Self.wallTime(date, clock, in: calendar))
        }

        private func apply(_ shift: Shift, to moment: Moment, in calendar: Calendar) throws -> Moment {
            var moment = moment
            for part in shift.parts {
                let amount = shift.sign * part.amount
                switch part.unit {
                case .calendar(let component, let multiple):
                    guard amount == amount.rounded() else { throw Failure.invalid }
                    let value = Int(amount) * multiple
                    switch moment {
                    case .civil(let date):
                        moment = .civil(try Self.adding(value, component, to: date))
                    case .instant(let date):
                        guard let shifted = calendar.date(byAdding: component, value: value, to: date) else { throw Failure.invalid }
                        moment = .instant(try Self.bounded(shifted))
                    }
                case .elapsed(let scale):
                    let seconds = amount * scale
                    guard abs(seconds - seconds.rounded()) < 1e-6 else { throw Failure.invalid }
                    let start: Date
                    switch moment {
                    case .civil(let date): start = try Self.startOfDay(date, in: calendar)
                    case .instant(let date): start = date
                    }
                    moment = .instant(try Self.bounded(start.addingTimeInterval(seconds.rounded())))
                }
            }
            return moment
        }

        private func difference(_ minuend: Moment, _ subtrahend: Moment, input: String) throws -> TemporalCalculation {
            switch (minuend, subtrahend) {
            case (.civil(let later), .civil(let earlier)):
                let days = try Self.days(from: earlier, to: later)
                let text = abs(days) == 1 ? "\(days) day" : "\(days) days"
                return TemporalCalculation(input: input, value: .civilDayDifference(days), title: text, subtitle: input, copyText: text)
            case (.instant(let later), .instant(let earlier)):
                let seconds = later.timeIntervalSince(earlier)
                let text = Self.elapsedText(seconds)
                return TemporalCalculation(input: input, value: .elapsed(seconds), title: text, subtitle: input, copyText: text)
            default:
                throw Failure.invalid
            }
        }

        private func civilResult(_ date: CivilDate, input: String) -> TemporalCalculation {
            let today = Self.civil(now, in: Self.gregorian(local.timeZone))
            let offset = (try? Self.days(from: today, to: date)) ?? 0
            let relative: String
            switch offset {
            case 0: relative = "today"
            case 1: relative = "tomorrow"
            case -1: relative = "yesterday"
            case 2...: relative = "in \(offset) days"
            default: relative = "\(-offset) days ago"
            }
            let instant = Self.utc.date(from: date.components) ?? now
            return TemporalCalculation(
                input: input,
                value: .civilDate(date),
                title: dateText(instant, zone: .gmt, year: date.year != today.year),
                subtitle: "\(input) · \(relative)",
                copyText: String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            )
        }

        private func instantResult(_ instant: Date, source: ResolvedZone, output: ResolvedZone, input: String) -> TemporalCalculation {
            let calendar = Self.gregorian(output.timeZone)
            let today = Self.civil(now, in: calendar)
            let day = Self.civil(instant, in: calendar)
            let seconds = calendar.component(.second, from: instant) != 0
            let time = timeText(instant, zone: output.timeZone, seconds: seconds)
            let title: String
            switch (try? Self.days(from: today, to: day)) ?? .max {
            case 0: title = "\(time) today"
            case 1: title = "\(time) tomorrow"
            case -1: title = "\(time) yesterday"
            default: title = "\(time), \(dateText(instant, zone: output.timeZone, year: day.year != today.year))"
            }
            var details = [input, "\(dateText(instant, zone: output.timeZone, year: true)) \(zoneText(output, at: instant))"]
            if source != output {
                let sourceTime = timeText(instant, zone: source.timeZone, seconds: seconds)
                details.append("\(dateText(instant, zone: source.timeZone, year: true)) \(sourceTime) \(zoneText(source, at: instant))")
            }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = output.timeZone
            return TemporalCalculation(
                input: input,
                value: .instant(instant, output.timeZone),
                title: title,
                subtitle: details.joined(separator: " · "),
                copyText: formatter.string(from: instant)
            )
        }

        private func timeText(_ instant: Date, zone: TimeZone, seconds: Bool) -> String {
            let style = Date.FormatStyle(date: .omitted, time: seconds ? .standard : .shortened, locale: locale, calendar: Self.gregorian(zone), timeZone: zone)
            return instant.formatted(style)
        }

        private func dateText(_ instant: Date, zone: TimeZone, year: Bool) -> String {
            let style = Date.FormatStyle(locale: locale, calendar: Self.gregorian(zone), timeZone: zone).weekday(.abbreviated).month(.abbreviated).day()
            return instant.formatted(year ? style.year() : style)
        }

        private func zoneText(_ zone: ResolvedZone, at instant: Date) -> String {
            guard !zone.label.hasPrefix("UTC") else { return zone.label }
            return "\(zone.label) (\(TimeZoneResolver.offsetLabel(zone.timeZone.secondsFromGMT(for: instant))))"
        }

        static func elapsedText(_ interval: TimeInterval) -> String {
            var rest = Int(abs(interval).rounded())
            var parts: [String] = []
            if rest >= 172_800 {
                parts.append("\(rest / 86_400) d")
                rest %= 86_400
            }
            for (size, unit) in [(3600, "h"), (60, "min"), (1, "s")] where rest >= size {
                parts.append("\(rest / size) \(unit)")
                rest %= size
            }
            guard !parts.isEmpty else { return "0 s" }
            return (interval < 0 ? "-" : "") + parts.joined(separator: " ")
        }

        private static func civil(_ instant: Date, in calendar: Calendar) -> CivilDate {
            let parts = calendar.dateComponents([.year, .month, .day], from: instant)
            return CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
        }

        private static func bounded(_ instant: Date) throws -> Date {
            guard supported.contains(instant) else { throw Failure.invalid }
            return instant
        }

        private static func validated(_ date: CivilDate) throws -> CivilDate {
            guard let instant = utc.date(from: date.components), supported.contains(instant), civil(instant, in: utc) == date else {
                throw Failure.invalid
            }
            return date
        }

        private static func adding(_ amount: Int, _ component: Calendar.Component, to date: CivilDate) throws -> CivilDate {
            guard let start = utc.date(from: date.components),
                  let end = utc.date(byAdding: component, value: amount, to: start) else { throw Failure.invalid }
            return try validated(civil(try bounded(end), in: utc))
        }

        private static func days(from start: CivilDate, to end: CivilDate) throws -> Int {
            guard let first = utc.date(from: start.components), let last = utc.date(from: end.components),
                  let days = utc.dateComponents([.day], from: first, to: last).day else { throw Failure.invalid }
            return days
        }

        private static func wallTime(_ date: CivilDate, _ clock: Clock, in calendar: Calendar) throws -> Date {
            let parts = DateComponents(year: date.year, month: date.month, day: date.day, hour: clock.hour, minute: clock.minute, second: clock.second)
            guard let instant = calendar.date(from: parts) else { throw Failure.invalid }
            let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
            guard back.year == date.year, back.month == date.month, back.day == date.day,
                  back.hour == clock.hour, back.minute == clock.minute, back.second == clock.second else { throw Failure.invalid }
            return try bounded(instant)
        }

        private static func startOfDay(_ date: CivilDate, in calendar: Calendar) throws -> Date {
            guard let instant = calendar.date(from: date.components), civil(instant, in: calendar) == date else { throw Failure.invalid }
            return try bounded(calendar.startOfDay(for: instant))
        }
    }
}
