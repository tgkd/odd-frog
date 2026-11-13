import Foundation

extension TemporalCalc {
    static func recognizePhrase(_ input: String, now: Date, timeZone: TimeZone, locale: Locale) -> Recognition? {
        let words = input.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        if words == ["week", "number"] || words == ["what", "week", "is", "it"] {
            let week = iso.component(.weekOfYear, from: now)
            let year = iso.component(.yearForWeekOfYear, from: now)
            return .value(TemporalCalculation(input: input, value: .weekNumber(week, year), title: "Week \(week), \(year)", subtitle: "ISO 8601 · \(input)", copyText: "\(year)-W\(String(format: "%02d", week))"))
        }
        if words.first == "week" {
            guard (2...3).contains(words.count), let week = Int(words[1]), (1...53).contains(week),
                  let year = words.count == 3 ? Int(words[2]) : iso.component(.yearForWeekOfYear, from: now), (1...9998).contains(year),
                  let start = iso.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year)),
                  iso.component(.weekOfYear, from: start) == week, iso.component(.yearForWeekOfYear, from: start) == year,
                  let end = iso.date(byAdding: .day, value: 6, to: start) else { return .rejected }
            let first = phraseCivil(start, calendar: calendar)
            let last = phraseCivil(end, calendar: calendar)
            let range = "\(phraseISO(first)) – \(phraseISO(last))"
            return .value(TemporalCalculation(input: input, value: .weekRange(first, last), title: range, subtitle: "ISO week \(week), \(year)", copyText: range))
        }
        if words == ["hours", "left", "in", "today"] {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return .rejected }
            let seconds = tomorrow.timeIntervalSince(now)
            let text = "\(CalculatorFormat.number(seconds / 3600, locale: locale)) h"
            return .value(TemporalCalculation(input: input, value: .elapsed(seconds), title: text, subtitle: input, copyText: text))
        }
        if words == ["days", "left", "in", "this", "month"] || words == ["days", "left", "in", "this", "year"] {
            let component: Calendar.Component = words.last == "month" ? .month : .year
            guard let period = calendar.dateInterval(of: component, for: today),
                  let last = calendar.date(byAdding: .day, value: -1, to: period.end),
                  let days = calendar.dateComponents([.day], from: today, to: last).day else { return .rejected }
            return phraseDays(days, input: input)
        }
        if words.count >= 3, words[0] == "days", words[1] == "since" || words[1] == "until" {
            let target = Array(words.dropFirst(2))
            let month: Int
            let day: Int
            if target == ["christmas"] { month = 12; day = 25 }
            else if (1...2).contains(target.count), let found = Parser.months[target[0]] {
                month = found
                guard let parsed = target.count == 2 ? Int(target[1]) : 1, (1...31).contains(parsed) else { return .rejected }
                day = parsed
            } else { return .rejected }
            let year = calendar.component(.year, from: today)
            let until = words[1] == "until"
            for offset in 0...8 {
                let candidateYear = year + (until ? offset : -offset)
                guard (1...9999).contains(candidateYear), let date = calendar.date(from: DateComponents(year: candidateYear, month: month, day: day)),
                      calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { continue }
                if until ? date >= today : date <= today {
                    guard let days = calendar.dateComponents([.day], from: until ? today : date, to: until ? date : today).day else { return .rejected }
                    return phraseDays(days, input: input)
                }
            }
            return .rejected
        }
        return nil
    }

    private static func phraseDays(_ days: Int, input: String) -> Recognition {
        let text = "\(days) \(days == 1 ? "day" : "days")"
        return .value(TemporalCalculation(input: input, value: .civilDayDifference(days), title: text, subtitle: input, copyText: text))
    }

    private static func phraseCivil(_ date: Date, calendar: Calendar) -> CivilDate {
        CivilDate(year: calendar.component(.year, from: date), month: calendar.component(.month, from: date), day: calendar.component(.day, from: date))
    }

    private static func phraseISO(_ date: CivilDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }
}
