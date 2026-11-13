import Foundation
import Testing
@testable import BundledFeatures

struct CalculatorReviewTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    private func calc(_ text: String, locale: Locale? = nil) -> QuickAction? {
        QuickAction.calculation(for: text, locale: locale ?? self.locale)
    }

    @Test func finiteLargeArithmeticIsAvailableWithoutChangingExactBaseOutput() throws {
        for (query, expected) in [("2^60", pow(2.0, 60)), ("10^20", 1e20), ("1e20", 1e20), ("2^53 + 2", 9_007_199_254_740_994.0), ("1e16 / 2", 5e15), ("0x10000000000000001 + 1", Double("18446744073709551617")! + 1)] {
            let action = try #require(calc(query), "\(query)")
            #expect(Arithmetic.evaluate(query) == expected, "\(query)")
            let copy = try #require(action.copyText)
            let value = try #require(Double(copy))
            #expect(abs(value / expected - 1) < 1e-14, "\(query)")
            #expect(action.answersQuery)
        }
        #expect(calc("2^60")?.title.contains("E") == true)
        #expect(calc("1e20")?.title.contains("E") == true)
        #expect(calc("0x10000000000000001")?.copyText == "18446744073709551617")
        #expect(calc("9007199254740993 in decimal")?.copyText == "9007199254740993")
        #expect(calc("42") == nil)
        #expect(calc("1e309") == nil)
        #expect(calc("10^309") == nil)
        #expect(calc("1e20.txt") == nil)
        #expect(calc("1e20 +") == nil)
    }

    @Test func siPrefixCaseDistinguishesMilliAndMega() throws {
        for (query, expected) in [("1 mW in W", 0.001), ("1 MW in W", 1e6), ("1 mHz in Hz", 0.001), ("1 MHz in Hz", 1e6), ("1 kW in W", 1000.0), ("1 kHz in Hz", 1000.0), ("1 MILLIWATT in W", 0.001), ("1 MEGAWATT in W", 1e6), ("1 MILLIHERTZ in Hz", 0.001), ("1 MEGAHERTZ in Hz", 1e6)] {
            let conversion = try #require(UnitConversion.evaluate(query), "\(query)")
            #expect(abs(conversion.value / expected - 1) < 1e-12)
        }
        #expect(UnitConversion.evaluate("1 mw in W") == nil)
        #expect(UnitConversion.evaluate("1 mhz in Hz") == nil)
        #expect(calc("sum(1 mW, 1 MW)") != nil)
        #expect(calc("1 MW in mW")?.copyText == "1000000000")
    }

    @Test func billsSplitWithOrWithoutTipVatOrDiscount() {
        for (query, title, copy) in [
            ("$60 split 3", "20.00 USD each", "20.00"),
            ("60 EUR split 3", "20.00 EUR each", "20.00"),
            ("15% tip on $80 split 4", "Tip 12.00 USD · Total 92.00 USD · 23.00 USD each", "23.00"),
            ("20% vat on $100 split 4", "VAT 20.00 USD · Total 120.00 USD · 30.00 USD each", "30.00"),
            ("20% vat in $120 split 4", "VAT 20.00 USD · Net 100.00 USD · 30.00 USD each", "30.00"),
            ("25% off $60 split 3", "15.00 USD each", "15.00"),
            ("($60 + $20) split 4", "20.00 USD each", "20.00")
        ] {
            #expect(calc(query)?.title == title, "\(query)")
            #expect(calc(query)?.copyText == copy, "\(query)")
        }
        for query in ["$60 split 0", "$60 split -2", "$60 split 1.5", "$60 split 3 extra", "$60 split 3 split 2", "15% tip on $80 split 0", "20% vat on 100 split 1.5"] {
            #expect(calc(query) == nil, "\(query)")
        }
    }

    @Test func moneyCopiesOneUngroupedNumber() {
        for (query, copy) in [
            ("15% tip on $80", "12.00"),
            ("20% vat in 120", "20.00"),
            ("20% vat on 100", "20.00"),
            ("25% off $60", "45.00"),
            ("sum($10, $10)", "20.00"),
            ("$1000 + $2000", "3000.00")
        ] {
            #expect(calc(query)?.copyText == copy, "\(query)")
        }
        #expect(calc("sum($10, $10)", locale: Locale(identifier: "de_DE"))?.copyText == "20,00")
        #expect(calc("$1000 + $2000", locale: Locale(identifier: "de_DE"))?.copyText == "3000,00")
    }

    @Test func kilobitAndKilobyteRatesAcceptUppercaseK() throws {
        for (query, expected) in [("1 Kbps in bps", 1000.0), ("1 KBps in bps", 8000.0), ("1 kbps in bps", 1000.0), ("1 kBps in bps", 8000.0)] {
            #expect(try #require(UnitConversion.evaluate(query)).value == expected)
        }
        #expect(calc("transfer 1 MB at 100 Kbps")?.title == "1 min 20 s")
        #expect(calc("transfer 1 MB at 100 KBps")?.title == "10 s")
    }
}
