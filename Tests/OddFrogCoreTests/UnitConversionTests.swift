import Foundation
import Testing
@testable import OddFrogCore

struct UnitConversionTests {
    private func expect(_ text: String, _ value: Double, result: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let conversion = UnitConversion.evaluate(text) else {
            Issue.record("\(text) did not convert", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(conversion.value - value) < 1e-3, "\(text) = \(conversion.value)", sourceLocation: sourceLocation)
        if let result {
            #expect(conversion.result == result, sourceLocation: sourceLocation)
        }
    }

    @Test func convertsAcrossDimensions() {
        expect("100 km in miles", 62.1371, result: "62.1371 mi")
        expect("50 kg to lb", 110.2312)
        expect("20 c in f", 68, result: "68°F")
        expect("512 gb in gib", 476.8372)
        expect("1.5h in min", 90)
        expect("2 cups in ml", 480, result: "480 mL")
    }

    @Test func acceptsEverySeparatorAndTheKeywordlessForm() {
        expect("100km mi", 62.1371)
        expect("100 km -> mi", 62.1371)
        expect("100 km → mi", 62.1371)
        expect("100 km = mi", 62.1371)
        expect("100 km as mi", 62.1371)
    }

    @Test func inchesResolveInUnitPositionOnly() {
        expect("5 in to cm", 12.7)
        expect("10 cm in in", 3.937)
        #expect(UnitConversion.evaluate("100 km in") == nil)
    }

    @Test func normalisesTheInputLine() {
        #expect(UnitConversion.evaluate("100 km in miles")?.input == "100 km → mi")
        #expect(UnitConversion.evaluate("20 c in f")?.input == "20 °C → °F")
    }

    @Test func rejectsMismatchedAndMalformedInput() {
        for text in ["100 kg in miles", "km in mi", "100 km in mi extra", "1,5 km in mi", "safari", "100", "2 min", "100 xyz in mi"] {
            #expect(UnitConversion.evaluate(text) == nil, "\(text) should not convert")
        }
    }
}
