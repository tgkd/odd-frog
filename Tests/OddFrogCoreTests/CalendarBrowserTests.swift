import Foundation
import Testing
import OddFrogCore

struct CalendarBrowserTests {
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

    @Test func untouchedViewFollowsTheDay() {
        var browser = CalendarBrowser(now: date("2026-12-31T23:00:00Z"), calendar: calendar())
        browser.refresh(now: date("2027-01-01T00:30:00Z"), calendar: calendar())
        #expect(browser.monthGrid.heading == "January 2027")

        var year = CalendarBrowser(now: date("2026-12-31T23:00:00Z"), calendar: calendar())
        year.show(.year)
        year.refresh(now: date("2027-01-01T00:30:00Z"), calendar: calendar())
        #expect(year.yearGrid.heading == "2027")
    }

    @Test func browsedViewStaysOnRefresh() {
        var browser = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        browser.step(by: 1)
        #expect(browser.monthGrid.heading == "October 2026")
        browser.refresh(now: date("2026-09-15T00:00:00Z"), calendar: calendar())
        #expect(browser.monthGrid.heading == "October 2026")
        #expect(browser.today == date("2026-09-15T00:00:00Z"))
    }

    @Test func yearModeStepsByYears() {
        var browser = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        browser.show(.year)
        browser.step(by: -1)
        #expect(browser.yearGrid.heading == "2025")

        var hebrew = CalendarBrowser(now: date("2024-01-15T00:00:00Z"), calendar: calendar(.hebrew))
        hebrew.show(.year)
        hebrew.step(by: 1)
        #expect(hebrew.yearGrid.heading == "5785")
        #expect(hebrew.yearGrid.months.count == 12)
    }

    @Test func steppingFromPeriodStartNeverSkipsAShortMonth() {
        var browser = CalendarBrowser(now: date("2027-01-31T00:00:00Z"), calendar: calendar())
        browser.step(by: 1)
        #expect(browser.monthGrid.heading == "February 2027")
    }

    @Test func zoneAndIdentifierChangesReset() {
        var browser = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        browser.step(by: 1)
        #expect(browser.browsed)
        browser.refresh(now: date("2026-09-15T00:00:00Z"), calendar: calendar(zone: "America/New_York"))
        #expect(!browser.browsed)
        #expect(browser.anchor == date("2026-09-15T00:00:00Z"))

        var hebrew = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        hebrew.step(by: 1)
        hebrew.refresh(now: date("2026-09-15T00:00:00Z"), calendar: calendar(.hebrew))
        #expect(!hebrew.browsed)
        #expect(hebrew.anchor == date("2026-09-15T00:00:00Z"))
    }

    @Test func firstWeekdayChangeKeepsTheBrowsedPeriod() {
        var browser = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        browser.step(by: 1)
        let first = browser.monthGrid.weekdays.first
        browser.refresh(now: date("2026-09-15T00:00:00Z"), calendar: calendar(firstWeekday: 2))
        #expect(browser.browsed)
        #expect(browser.monthGrid.heading == "October 2026")
        #expect(browser.monthGrid.weekdays.first != first)
    }

    @Test func presentAndTodayResetBrowsing() {
        var browser = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        browser.show(.year)
        browser.step(by: 1)
        browser.present(now: date("2026-10-01T00:00:00Z"), calendar: calendar())
        #expect(browser.mode == .month)
        #expect(!browser.browsed)
        #expect(browser.anchor == date("2026-10-01T00:00:00Z"))

        var year = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        year.show(.year)
        year.goToToday(now: date("2026-10-01T00:00:00Z"), calendar: calendar())
        #expect(year.mode == .year)
        #expect(!year.browsed)
        #expect(year.anchor == date("2026-10-01T00:00:00Z"))
    }

    @Test func openingATileShowsThatMonth() {
        var browser = CalendarBrowser(now: date("2026-09-14T00:00:00Z"), calendar: calendar())
        browser.open(month: date("2026-11-05T00:00:00Z"))
        #expect(browser.mode == .month)
        #expect(browser.monthGrid.heading == "November 2026")
        #expect(browser.browsed)

        let anchor = browser.anchor
        let browsed = browser.browsed
        browser.show(.year)
        #expect(browser.browsed == browsed)
        #expect(browser.anchor == anchor)
    }
}
