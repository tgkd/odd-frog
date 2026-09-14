import Foundation
import Testing
@testable import BundledFeatures

struct TemporalCalcTests {
    private let now = Date(timeIntervalSince1970: 1_789_378_200.4)
    private let moscow = TimeZone(identifier: "Europe/Moscow") ?? .gmt
    private let posix = Locale(identifier: "en_US_POSIX")

    private func calc(_ text: String) -> QuickAction? {
        QuickAction.calculation(for: text, now: now, timeZone: moscow, locale: posix)
    }

    private func title(_ text: String) -> String? {
        calc(text)?.title.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func copy(_ text: String) -> String? {
        calc(text)?.copyText
    }

    @Test func zonedTimeShowsInLocalTime() {
        let action = calc("10PM UTC")
        #expect(title("10PM UTC") == "1:00 AM tomorrow")
        #expect(action?.copyText == "2026-09-15T01:00:00+03:00")
        #expect(action?.kindLabel == "Time")
        #expect(action?.id == "quick:calc:10PM UTC")
        #expect(action?.subtitle.map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
            == "10PM UTC · Tue, Sep 15, 2026 Moscow (UTC+3) · Mon, Sep 14, 2026 10:00 PM UTC")
    }

    @Test func shiftsAndConvertsTimes() {
        #expect(title("10pm utc - 3h") == "10:00 PM today")
        #expect(copy("10pm utc - 3h") == "2026-09-14T22:00:00+03:00")
        #expect(copy("10pm utc in tokyo") == "2026-09-15T07:00:00+09:00")
        #expect(title("now in tokyo") == "6:30 PM today")
        #expect(copy("now → new york") == "2026-09-14T05:30:00-04:00")
        #expect(copy("10pm utc + 1.5h") == "2026-09-15T02:30:00+03:00")
        #expect(title("10pm utc + 1s") == "1:00:01 AM tomorrow")
        #expect(copy("sep 20 at 9am pt") == "2026-09-20T19:00:00+03:00")
    }

    @Test func civilDatesStayDates() {
        let action = calc("today + 3d")
        #expect(title("today + 3d") == "Thu, Sep 17")
        #expect(action?.copyText == "2026-09-17")
        #expect(action?.kindLabel == "Date")
        #expect(action?.subtitle == "today + 3d · in 3 days")
        #expect(title("sep 30 - today") == "16 days")
        #expect(title("today - sep 30") == "-16 days")
        #expect(title("2026-09-20 - 2026-09-14") == "6 days")
        #expect(copy("today utc") == "2026-09-14")
    }

    @Test func calendarArithmeticClampsInWrittenOrder() {
        #expect(copy("jan 31 + 1mo") == "2026-02-28")
        #expect(copy("jan 31 + 1mo + 1mo") == "2026-03-28")
        #expect(copy("jan 31 + 2mo") == "2026-03-31")
        #expect(copy("2028-02-29 + 1y") == "2029-02-28")
    }

    @Test func isoDatesAreReservedFromArithmetic() {
        #expect(calc("2026-09-20") == nil)
        #expect(calc("2026-02-30") == nil)
        #expect(calc("2026-02-30 + 1d") == nil)
        #expect(calc("2026 - 9 - 20")?.kindLabel == "Calculator")
        #expect(copy("2026 - 9 - 20") == "1997")
    }

    @Test func leavesOtherQueriesToOtherEvaluators() {
        #expect(calc("3h in min")?.kindLabel == "Units")
        #expect(calc("2+2")?.kindLabel == "Calculator")
        #expect(calc("10pm") == nil)
        #expect(calc("sep 20") == nil)
        #expect(calc("now") == nil)
        #expect(calc("42") == nil)
        #expect(calc("safari") == nil)
    }

    @Test func rejectsMalformedTemporalInput() {
        #expect(calc("10pm utc -") == nil)
        #expect(calc("10pm utc junk") == nil)
        #expect(calc("24:00 utc") == nil)
        #expect(calc("13pm utc") == nil)
        #expect(calc("10pm utc+05:60") == nil)
        #expect(calc("today + 1.5d") == nil)
        #expect(calc("10pm utc + 0.5s") == nil)
        #expect(calc("dec 25 - now") == nil)
        #expect(calc("sep 20 in tokyo") == nil)
        #expect(calc("sep 30 - today in tokyo") == nil)
        #expect(calc("10pm ist") == nil)
        #expect(calc("10pm bst") == nil)
    }

    @Test func parsesClockEdgesAndOffsets() {
        #expect(copy("12am utc") == "2026-09-14T03:00:00+03:00")
        #expect(copy("12pm utc") == "2026-09-14T15:00:00+03:00")
        #expect(copy("10pm UTC-05:30 - 3h") == "2026-09-15T03:30:00+03:00")
        #expect(copy("10pm utc-3h") == "2026-09-14T22:00:00+03:00")
        #expect(copy("2026-09-20t22:00z") == "2026-09-21T01:00:00+03:00")
        #expect(copy("2026-09-20T22:00+03:00") == "2026-09-20T22:00:00+03:00")
        #expect(copy("10pm cst in utc") == "2026-09-15T04:00:00Z")
        #expect(copy("10pm ct in utc") == "2026-09-15T03:00:00Z")
    }

    @Test func subtractsInstantsAsElapsedTime() {
        #expect(title("10pm utc - 9pm utc") == "1 h")
        #expect(title("sep 16 10am utc - sep 14 8am utc") == "2 d 2 h")
        #expect(title("9pm utc - 10:30pm utc") == "-1 h 30 min")
    }

    @Test func handlesDaylightSavingTransitions() {
        #expect(calc("2026-03-08 2:30am et") == nil)
        #expect(copy("2026-03-07 3:00am et + 1d in et") == "2026-03-08T03:00:00-04:00")
        #expect(copy("2026-03-07 3:00am et + 24h in et") == "2026-03-08T04:00:00-04:00")
        #expect(copy("2026-03-07 2:30am et + 1d in et") == "2026-03-08T03:30:00-04:00")
        #expect(copy("2026-11-01 1:30am et in utc") == "2026-11-01T05:30:00Z")
    }

    @Test func handlesSkippedDatesAndMidnights() {
        #expect(copy("2011-12-29 pacific/apia + 1d") == "2011-12-30")
        #expect(calc("2011-12-30 pacific/apia + 1h") == nil)
        #expect(copy("2011-12-29 12:00 pacific/apia + 1d in pacific/apia") == "2011-12-31T12:00:00+14:00")
        #expect(copy("2026-09-06 santiago + 1h in santiago") == "2026-09-06T02:00:00-03:00")
    }
}

struct TimeZoneResolverTests {
    @Test func resolvesIdentifiersAliasesAndCities() {
        #expect(TimeZoneResolver.zone(named: "America/New_York")?.timeZone.identifier == "America/New_York")
        #expect(TimeZoneResolver.zone(named: "india")?.timeZone.identifier == "Asia/Kolkata")
        #expect(TimeZoneResolver.zone(named: "tokyo")?.timeZone.identifier == "Asia/Tokyo")
        #expect(TimeZoneResolver.zone(named: "new york")?.label == "New York")
        #expect(TimeZoneResolver.zone(named: "et")?.timeZone.identifier == "America/New_York")
    }

    @Test func fixedAbbreviationsKeepTheirOffset() {
        let zone = TimeZoneResolver.zone(named: "cst")
        #expect(zone?.label == "CST")
        #expect(zone?.timeZone.secondsFromGMT() == -6 * 3600)
        #expect(TimeZoneResolver.zone(named: "ist") == nil)
        #expect(TimeZoneResolver.zone(named: "bst") == nil)
    }

    @Test func ambiguousCitySuffixesNeedTheFullIdentifier() {
        let index = TimeZoneResolver.suffixIndex(["Asia/Tokyo", "Pacific/Tokyo", "Europe/London"])
        #expect(index["tokyo"]?.count == 2)
        #expect(TimeZoneResolver.zone(named: "tokyo", suffixes: index) == nil)
        #expect(TimeZoneResolver.zone(named: "london", suffixes: index)?.timeZone.identifier == "Europe/London")
        #expect(TimeZoneResolver.zone(named: "asia/tokyo", suffixes: index)?.timeZone.identifier == "Asia/Tokyo")
    }

    @Test func offsetsAreBounded() {
        #expect(TimeZoneResolver.zone(offsetSign: -1, hours: 5, minutes: 30)?.label == "UTC-5:30")
        #expect(TimeZoneResolver.zone(offsetSign: 1, hours: 15, minutes: 0) == nil)
        #expect(TimeZoneResolver.zone(offsetSign: 1, hours: 5, minutes: 60) == nil)
    }
}
