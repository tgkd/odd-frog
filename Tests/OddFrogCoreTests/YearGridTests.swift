import Foundation
import Testing
import OddFrogCore

struct YearGridTests {
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

    @Test func gregorianYearHasTwelveMonthsAndMarksOneDay() {
        let grid = YearGrid(year: date("2026-09-14T00:00:00Z"), today: date("2026-09-14T00:00:00Z"), calendar: calendar())
        #expect(grid.heading == "2026")
        #expect(grid.months.count == 12)
        #expect(grid.months.first?.heading == "January 2026")
        let today = grid.months.flatMap(\.days).filter(\.isToday)
        #expect(today.count == 1)
        #expect(today.first?.number == "14")
    }

    @Test func hebrewLeapYearHasThirteenMonthsInOrder() {
        let grid = YearGrid(year: date("2024-01-15T00:00:00Z"), today: date("2024-01-15T00:00:00Z"), calendar: calendar(.hebrew))
        #expect(grid.heading == "5784")
        #expect(grid.months.count == 13)
        let names = grid.months.map(\.name)
        #expect(names.contains("Adar I"))
        #expect(names.contains("Adar II"))
        #expect(names.firstIndex(of: "Adar I")! < names.firstIndex(of: "Adar II")!)
    }

    @Test func hebrewCommonYearHasTwelveMonths() {
        let grid = YearGrid(year: date("2025-01-15T00:00:00Z"), today: date("2025-01-15T00:00:00Z"), calendar: calendar(.hebrew))
        #expect(grid.heading == "5785")
        #expect(grid.months.count == 12)
    }
}
