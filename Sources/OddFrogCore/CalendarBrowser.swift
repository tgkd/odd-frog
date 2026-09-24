import Foundation

public struct CalendarBrowser: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case month, year }

    public private(set) var mode: Mode
    public private(set) var anchor: Date
    public private(set) var today: Date
    public private(set) var calendar: Calendar
    public private(set) var browsed: Bool

    public init(now: Date, calendar: Calendar) {
        mode = .month
        anchor = now
        today = now
        self.calendar = calendar
        browsed = false
    }

    public var monthGrid: MonthGrid { MonthGrid(month: anchor, today: today, calendar: calendar) }
    public var yearGrid: YearGrid { YearGrid(year: anchor, today: today, calendar: calendar) }

    public mutating func present(now: Date, calendar: Calendar) {
        mode = .month
        goToToday(now: now, calendar: calendar)
    }

    public mutating func goToToday(now: Date, calendar: Calendar) {
        self.calendar = calendar
        today = now
        anchor = now
        browsed = false
    }

    public mutating func show(_ mode: Mode) {
        self.mode = mode
    }

    public mutating func step(by count: Int) {
        let component: Calendar.Component = mode == .month ? .month : .year
        guard let start = calendar.dateInterval(of: component, for: anchor)?.start,
              let stepped = calendar.date(byAdding: component, value: count, to: start) else {
            return
        }
        anchor = stepped
        browsed = true
    }

    public mutating func open(month: Date) {
        mode = .month
        anchor = month
        browsed = true
    }

    public mutating func refresh(now: Date, calendar: Calendar) {
        if calendar.identifier != self.calendar.identifier || calendar.timeZone != self.calendar.timeZone {
            browsed = false
        }
        self.calendar = calendar
        today = now
        if !browsed {
            anchor = now
        }
    }
}
