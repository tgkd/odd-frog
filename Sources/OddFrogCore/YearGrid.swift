import Foundation

public struct YearGrid: Equatable, Sendable {
    public let year: Date
    public let heading: String
    public let months: [MonthGrid]

    public init(year anchor: Date, today: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .year, for: anchor)!
        year = interval.start
        heading = MonthGrid.formatter(calendar, template: "y").string(from: year)
        var months: [MonthGrid] = []
        var current = interval.start
        while current < interval.end {
            months.append(MonthGrid(month: current, today: today, calendar: calendar))
            guard let next = calendar.date(byAdding: .month, value: 1, to: current), next > current else {
                break
            }
            current = next
        }
        self.months = months
    }
}
