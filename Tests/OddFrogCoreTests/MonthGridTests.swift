import Foundation
import Testing
import OddFrogCore

struct MonthGridTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func calendar(_ identifier: Calendar.Identifier = .gregorian, zone: String = "UTC", firstWeekday: Int? = nil) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US")
        if let firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    @Test func septemberStartsOnTheUsersFirstWeekdayAndMarksToday() {
        let grid = MonthGrid(month: date("2026-09-20T10:00:00Z"), today: date("2026-09-14T09:00:00Z"),
                             calendar: calendar(firstWeekday: 1))
        #expect(grid.heading == "September 2026")
        #expect(grid.name == "September")
        #expect(grid.month == date("2026-09-01T00:00:00Z"))
        #expect(grid.weekdays.first == "Sun")
        #expect(grid.narrowWeekdays == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(grid.days.count == 42)
        #expect(grid.days.first?.date == date("2026-08-30T00:00:00Z"))
        #expect(grid.days.filter(\.inMonth).count == 30)
        let today = grid.days.filter(\.isToday)
        #expect(today.count == 1)
        #expect(today.first?.label == "Monday, September 14, 2026")
        #expect(today.first?.number == "14")

        let monday = MonthGrid(month: date("2026-09-20T10:00:00Z"), today: date("2026-09-14T09:00:00Z"),
                               calendar: calendar(firstWeekday: 2))
        #expect(monday.weekdays == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(monday.days.first?.date == date("2026-08-31T00:00:00Z"))
    }

    @Test func februaryHandlesNoLeadingDaysAndLeapYears() {
        let today = date("2026-09-14T00:00:00Z")
        let february = MonthGrid(month: date("2026-02-10T00:00:00Z"), today: today, calendar: calendar(firstWeekday: 1))
        #expect(february.days.first?.date == date("2026-02-01T00:00:00Z"))
        #expect(february.days.filter(\.inMonth).count == 28)
        let leap = MonthGrid(month: date("2028-02-10T00:00:00Z"), today: today, calendar: calendar(firstWeekday: 1))
        #expect(leap.days.filter(\.inMonth).count == 29)
    }

    @Test func shiftingCrossesYearsAndNeverSkipsShortMonths() {
        let gregorian = calendar()
        let today = date("2026-09-14T00:00:00Z")
        func heading(_ anchor: Date) -> String { MonthGrid(month: anchor, today: today, calendar: gregorian).heading }
        #expect(heading(MonthGrid.shifted(date("2026-12-15T00:00:00Z"), months: 1, calendar: gregorian)) == "January 2027")
        #expect(heading(MonthGrid.shifted(date("2027-01-15T00:00:00Z"), months: -1, calendar: gregorian)) == "December 2026")
        #expect(heading(MonthGrid.shifted(date("2027-01-31T00:00:00Z"), months: 1, calendar: gregorian)) == "February 2027")
    }

    @Test func hebrewNavigationStepsThroughLeapMonths() {
        let hebrew = calendar(.hebrew)
        let today = date("2026-09-14T00:00:00Z")
        var anchor = date("2023-09-16T00:00:00Z")
        var headings = [MonthGrid(month: anchor, today: today, calendar: hebrew).heading]
        for _ in 0..<13 {
            anchor = MonthGrid.shifted(anchor, months: 1, calendar: hebrew)
            let grid = MonthGrid(month: anchor, today: today, calendar: hebrew)
            headings.append(grid.heading)
            if grid.heading == "Adar I 5784" {
                #expect(grid.name == "Adar I")
                #expect(grid.days.filter(\.inMonth).count == 30)
            }
        }
        #expect(headings == ["Tishri 5784", "Heshvan 5784", "Kislev 5784", "Tevet 5784", "Shevat 5784", "Adar I 5784",
                             "Adar II 5784", "Nisan 5784", "Iyar 5784", "Sivan 5784", "Tamuz 5784", "Av 5784",
                             "Elul 5784", "Tishri 5785"])
        #expect(anchor == date("2024-10-03T00:00:00Z"))
    }

    @Test func daysAreCivilMidnightsAcrossDaylightSaving() {
        let newYork = calendar(zone: "America/New_York")
        let grid = MonthGrid(month: date("2026-03-15T12:00:00Z"), today: date("2026-09-14T00:00:00Z"), calendar: newYork)
        #expect(grid.days.allSatisfy { newYork.component(.hour, from: $0.date) == 0 })
        #expect(grid.days.filter(\.inMonth).map(\.number) == (1...31).map(String.init))
    }
}
