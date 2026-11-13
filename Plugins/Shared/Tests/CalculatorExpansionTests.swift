import Foundation
import Testing
@testable import BundledFeatures

struct CalculatorExpansionTests {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let now = ISO8601DateFormatter().date(from: "2026-11-13T12:00:00Z")!
    private let zone = TimeZone(identifier: "Europe/Belgrade")!

    private func calc(_ text: String, at instant: Date? = nil, in timeZone: TimeZone? = nil) -> QuickAction? {
        QuickAction.calculation(for: text, now: instant ?? now, timeZone: timeZone ?? zone, locale: locale)
    }

    @Test func signedAndScientificLiteralsConvert() throws {
        #expect(abs(try #require(UnitConversion.evaluate("-10 c in f")).value - 14) < 1e-10)
        #expect(abs(try #require(UnitConversion.evaluate("−10 C IN F")).value - 14) < 1e-10)
        #expect(try #require(UnitConversion.evaluate("1e3 m in km")).value == 1)
        let rates = CurrencyRates(base: "USD", timestamp: now, rates: ["USD": 1, "EUR": 0.8])
        #expect(try #require(CurrencyConversion.evaluate("-10 USD in EUR", rates: rates)).value == -8)
        #expect(try #require(CurrencyConversion.evaluate("$-1e2 in EUR", rates: rates)).value == -80)
        #expect(try #require(CurrencyConversion.evaluate("-$10 in EUR", rates: rates)).value == -8)
        let tinyRates = CurrencyRates(base: "USD", timestamp: now, rates: ["USD": 1, "EUR": 1e-12])
        let tinyCurrency = try #require(QuickAction.calculation(for: "1 USD in EUR", rates: tinyRates, locale: locale))
        #expect(Double(tinyCurrency.copyText ?? "") == 1e-12)
        #expect(tinyCurrency.title != "0.00 EUR")
        #expect(Arithmetic.evaluate("1e3 + 1") == 1001)
        #expect(Arithmetic.evaluate("1E-3 * 2") == 0.002)
        #expect(Arithmetic.evaluate("1e + 1") == nil)
        #expect(Arithmetic.evaluate("1e309 + 1") == nil)
    }

    @Test func smallNonzeroResultsSurviveDisplayAndCopy() throws {
        let action = try #require(calc("1 bit in tb"))
        #expect(action.title != "0 TB")
        let copyText = try #require(action.copyText)
        let copied = try #require(Double(copyText))
        #expect(copied > 0)
        #expect(abs(copied - 1.25e-13) < 1e-25)
        let tiny = try #require(calc("1e-12 / 8"))
        let tinyText = try #require(tiny.copyText)
        #expect(Double(tinyText) == 1.25e-13)
        let german = try #require(QuickAction.calculation(for: "1 bit in tb", locale: Locale(identifier: "de_DE")))
        #expect(german.title.contains(","))
        #expect(german.copyText?.contains(",") == true)
    }

    @Test func symbolsDistinguishBitsBytesAndRates() throws {
        for (query, expected) in [("1 MB in bit", 8e6), ("1 Mb in bit", 1e6), ("1 B in b", 8), ("1 MiB in bit", 8_388_608), ("1 MEGABYTE in bit", 8e6), ("1 Mbps in bps", 1e6), ("1 MBps in bps", 8e6), ("1 KB in bit", 8000), ("1 Kb in bit", 1000), ("1 kb in bit", 8000), ("1 gb in bit", 8e9)] {
            #expect(try #require(UnitConversion.evaluate(query)).value == expected)
        }
        #expect(UnitConversion.evaluate("1 Mbps in MB") == nil)
        #expect(UnitConversion.evaluate("1 mbps in bps") == nil)
        #expect(UnitConversion.evaluate("1 mB in bit") == nil)
    }

    @Test func scalarFunctionsAndConstants() throws {
        for (query, expected) in [("round(23.456, 1)", 23.5), ("round(125, -1)", 130), ("round(-1.5)", -2), ("floor(-1.2)", -2), ("ceil(-1.2)", -1), ("abs(-3)", 3), ("sqrt(9)", 3), ("sum(1, 2, 3)", 6), ("avg(1, 2, 3)", 2), ("min(3, 1, 2)", 1), ("max(3, 1, 2)", 3), ("sum(1, max(2, 3), sqrt(4))", 6), ("0x10 + 0b10 + 0o10", 26), ("49 / 49", 1)] {
            #expect(Arithmetic.evaluate(query) == expected, "\(query)")
            #expect(calc(query)?.answersQuery == true)
        }
        #expect(try #require(Arithmetic.evaluate("e")) == M_E)
        #expect(try #require(Arithmetic.evaluate("pi")) == .pi)
        #expect(calc("e")?.answersQuery == true)
        #expect(calc("pi")?.answersQuery == true)
        for text in ["sum()", "sum(1,)", "sqrt(-1)", "round(1, 0.5)", "floor(1, 2)", "wat(1)", "sum(1 2)", "sqrt(1) extra", "1e", "1e+", "0b2 + 1"] {
            #expect(calc(text) == nil, "\(text)")
        }
    }

    @Test func exactRepresentationsAndNearestSteps() {
        for (query, copy) in [("255 in hex", "ff"), ("255 in binary", "11111111"), ("255 in octal", "377"), ("35 in base 36", "z"), ("0xff", "255"), ("-0b101", "-5"), ("0o10 in hex", "8"), ("18446744073709551616 in hex", "10000000000000000"), ("0x10000000000000001", "18446744073709551617"), ("9007199254740993 in decimal", "9007199254740993"), ("9007199254740990 + 1", "9007199254740991"), ("1.75 as fraction", "7/4"), ("1.75 as improper", "7/4"), ("1.75 as mixed", "1 3/4"), ("-1.75 as mixed", "-1 3/4"), ("0 as fraction", "0"), ("0.125 as fraction", "1/8"), ("3.3 to nearest quarter", "3.25"), ("3.3 to nearest half", "3.5"), ("3.34 to nearest tenth", "3.3"), ("13 to nearest 5", "15")] {
            #expect(calc(query)?.copyText == copy, "\(query)")
        }
        for query in ["255 in base 1", "255 in base 37", "1.5 in hex", "0xgg", "--0xff", "0b102", "3 to nearest 0", "3 to nearest -1", "1e100 as fraction"] {
            #expect(calc(query) == nil, "\(query)")
        }
    }

    @Test func quantityFunctionsComposeAndRejectDimensionMismatches() {
        #expect(calc("max(2 hours 30 min, 200 min)")?.title == "200 min")
        #expect(calc("sum(1 h, 30 min)")?.title == "1.5 hr")
        #expect(calc("2 h + 30 min")?.kindLabel == "Units")
        #expect(calc("avg(1 m, 300 cm)")?.title == "2 m")
        #expect(Arithmetic.evaluate("2 h / 30 min") == 4)
        for query in ["max(1 h, 2 m)", "sum(1 h, 2)", "sum(1 c, 2 c)", "1 m * 2 m", "1 h / 0 min"] {
            #expect(calc(query) == nil, "\(query)")
        }
    }

    @Test func moneyUsesInclusiveVatAndLabelsTipTotalAndSplit() {
        #expect(calc("15% tip on $80")?.title == "Tip 12.00 USD · Total 92.00 USD")
        #expect(calc("20% vat in 120")?.title == "VAT 20.00 · Net 100.00")
        #expect(calc("20% vat on 100")?.title == "VAT 20.00 · Total 120.00")
        #expect(calc("25% off $60 split 3")?.title == "15.00 USD each")
        #expect(calc("25% off 60 EUR split 3")?.title == "15.00 EUR each")
        #expect(calc("sum($0.1, $0.2)")?.title == "0.30 USD")
        #expect(calc("$60 - 25%")?.title == "45.00 USD")
        #expect(calc("($60 - 25%) / 3")?.title == "15.00 USD")
        #expect(QuickAction.calculation(for: "15% tip on $80", defaultCurrency: "CAD", locale: locale)?.title == "Tip 12.00 CAD · Total 92.00 CAD")
        for query in ["20% vat in 120 junk", "25% off $60 split 0", "25% off $60 split 1.5", "101% off $60", "-1% tip on $80", "sum($1, €2)", "$1 / 0", "20% vat on 1e309"] {
            #expect(calc(query) == nil, "\(query)")
        }
    }

    @Test func expandsUnitsAndPhysicalConstants() throws {
        for (query, expected) in [("1 kHz in Hz", 1000.0), ("1 bar in kPa", 100.0), ("1 kJ in J", 1000.0), ("1 kW in W", 1000.0), ("180 deg in rad", Double.pi), ("1 km/s in m/s", 1000.0), ("1 m3 in l", 1000.0)] {
            let value = try #require(UnitConversion.evaluate(query)).value
            #expect(abs(value - expected) < 1e-8)
        }
        #expect(calc("speed of light in km/s")?.copyText == "299792.458 km/s")
        #expect(calc("c in km/s")?.copyText == "299792.458 km/s")
        #expect(calc("absolute zero in c")?.title == "-273.15°C")
        #expect(abs(try #require(UnitConversion.evaluate("10 c in f")).value - 50) < 1e-10)
    }

    @Test func transferAndReciprocalPace() {
        #expect(calc("transfer 1 TB at 100 Mbps")?.title == "22 h 13 min 20 s")
        #expect(calc("transfer 1 TB at 100 MBps")?.title == "2 h 46 min 40 s")
        #expect(calc("5:00 min/km in km/h")?.title == "12 km/h")
        #expect(calc("12 km/h in min/km")?.title == "5:00 min/km")
        #expect(calc("5 min/km in km/h")?.title == "12 km/h")
        for query in ["transfer 1 TB at 0 Mbps", "transfer -1 TB at 100 Mbps", "transfer 1 km at 100 Mbps", "5:60 min/km in km/h", "0:00 min/km in km/h", "0 km/h in min/km", "-5:00 min/km in km/h"] {
            #expect(calc(query) == nil, "\(query)")
        }
    }

    @Test func calendarPhraseDefaultsAreExplicit() {
        #expect(calc("week 44 2026")?.copyText == "2026-10-26 – 2026-11-01")
        #expect(calc("week 44")?.copyText == "2026-10-26 – 2026-11-01")
        #expect(calc("week number")?.copyText == "2026-W46")
        #expect(calc("what week is it")?.copyText == "2026-W46")
        #expect(calc("days left in this month")?.title == "17 days")
        #expect(calc("days left in this year")?.title == "48 days")
        #expect(calc("hours left in today")?.title == "11 h")
        #expect(calc("days since march")?.title == "257 days")
        #expect(calc("days until christmas")?.title == "42 days")
        for query in ["week 0", "week 54", "week 53 2025", "week 1 0", "days since march 99", "days until nonsense"] {
            #expect(calc(query) == nil, "\(query)")
        }
        let january = ISO8601DateFormatter().date(from: "2027-01-01T12:00:00Z")!
        #expect(calc("week number", at: january)?.copyText == "2026-W53")
        #expect(calc("days since march", at: january)?.title == "306 days")
        #expect(calc("days left in this month", at: ISO8601DateFormatter().date(from: "2026-11-30T12:00:00Z")!)?.title == "0 days")
    }

    @Test func zoneAliasesAndShiftsUseWrittenOrder() {
        #expect(calc("time in Brisbane")?.copyText == "2026-11-13T22:00:00+10:00")
        #expect(calc("time in Brisbane + 4")?.copyText == "2026-11-14T02:00:00+10:00")
        #expect(calc("now in Brisbane + 4h")?.copyText == "2026-11-14T02:00:00+10:00")
        #expect(calc("4:00 PT in UTC")?.copyText == "2026-11-13T12:00:00Z")
        #expect(calc("4:00 PT + 4 in UTC")?.copyText == "2026-11-13T16:00:00Z")
        #expect(calc("today + 4") == nil)
        #expect(calc("now + 4") == nil)
        #expect(calc("today in Brisbane + 4") == nil)
        #expect(calc("2026-03-07 12:00 utc in et + 1d")?.copyText == "2026-03-08T07:00:00-04:00")
        #expect(calc("2026-03-07 12:00 utc + 1d in et")?.copyText == "2026-03-08T08:00:00-04:00")
    }

    @Test func remainingHoursRespectShortAndLongLocalDays() {
        let eastern = TimeZone(identifier: "America/New_York")!
        #expect(calc("hours left in today", at: ISO8601DateFormatter().date(from: "2026-03-08T05:00:00Z")!, in: eastern)?.title == "23 h")
        #expect(calc("hours left in today", at: ISO8601DateFormatter().date(from: "2026-11-01T04:00:00Z")!, in: eastern)?.title == "25 h")
    }

    @Test func launcherAmbiguityAndInputBudgetsRemainBounded() {
        #expect(calc("2024-03")?.answersQuery == false)
        #expect(calc("1920x1080")?.answersQuery == false)
        #expect(calc("2026-02-30 + 1d") == nil)
        #expect(calc("e.txt") == nil)
        #expect(calc("sum.txt") == nil)
        #expect(calc(String(repeating: "-", count: 500) + "1+1") == nil)
        #expect(calc(String(repeating: "(", count: 100) + "1+1" + String(repeating: ")", count: 100)) == nil)
        #expect(calc(String(repeating: "9", count: 5000) + " in hex") == nil)
    }
}
