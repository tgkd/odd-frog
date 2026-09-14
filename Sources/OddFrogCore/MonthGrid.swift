import Foundation

public struct MonthGrid: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let date: Date
        public let number: String
        public let inMonth: Bool
        public let isToday: Bool
        public let label: String
    }

    public let month: Date
    public let heading: String
    public let weekdays: [String]
    public let days: [Day]

    public init(month anchor: Date, today: Date, calendar: Calendar) {
        let start = calendar.dateInterval(of: .month, for: anchor)!.start
        month = start
        heading = MonthGrid.formatter(calendar, template: "MMMMy").string(from: start)
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let rotation = (calendar.firstWeekday - 1) % symbols.count
        weekdays = Array(symbols[rotation...] + symbols[..<rotation])
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -leading, to: start)!
        let number = MonthGrid.formatter(calendar, template: "d")
        let label = MonthGrid.formatter(calendar, template: nil)
        days = (0..<42).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: first)!
            return Day(date: date, number: number.string(from: date),
                       inMonth: calendar.isDate(date, equalTo: start, toGranularity: .month),
                       isToday: calendar.isDate(date, inSameDayAs: today), label: label.string(from: date))
        }
    }

    public static func shifted(_ anchor: Date, months: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: months, to: calendar.dateInterval(of: .month, for: anchor)!.start)!
    }

    private static func formatter(_ calendar: Calendar, template: String?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        } else {
            formatter.dateStyle = .full
            formatter.timeStyle = .none
        }
        return formatter
    }
}
