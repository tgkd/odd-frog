import Foundation
import Testing
@testable import OddFrogCore
@testable import BundledFeatures

struct ArithmeticTests {
    private func expect(_ text: String, _ expected: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let value = Arithmetic.evaluate(text) else {
            Issue.record("\(text) did not evaluate", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(value - expected) < 1e-9, "\(text) = \(value)", sourceLocation: sourceLocation)
    }

    @Test func evaluatesBasicArithmetic() {
        expect("2+2", 4)
        expect("5 * (20 + 4) / 3", 40)
        expect(".5 + .25", 0.75)
        expect("5 ÷ 2", 2.5)
        expect("3x4", 12)
        expect("3 × 4", 12)
    }

    @Test func powerBindsTighterThanUnaryMinusAndIsRightAssociative() {
        expect("-2^2", -4)
        expect("2^3^2", 512)
    }

    @Test func percentIsRelativeOnlyForAdditionAndSubtraction() {
        expect("500 + 20%", 600)
        expect("500 - 20%", 400)
        expect("500 * 20%", 100)
        expect("20% of 500", 100)
        expect("20%", 0.2)
    }

    @Test func onlyOperatorsNoNameUsesMakeAPlainCalculation() {
        for text in ["2+2", "5 * 3", "10 - 3", "10 / 2", "20% of 500", "(1)-2", "3×4"] {
            #expect(Arithmetic.isPlainCalculation(text), "\(text) should be plain")
        }
        for text in ["2024-03", "10/2023", "1920x1080", "123-45-67", "1 of 3", "10-3"] {
            #expect(Arithmetic.evaluate(text) != nil && !Arithmetic.isPlainCalculation(text), "\(text) should be ambiguous")
        }
    }

    @Test func rejectsNonExpressions() {
        for text in ["42", "(42)", "1,000", "2 +", "cal 2", "1/0", "2 ** 3", "hello", "", "  ", "safari", "1.2.3", "x2"] {
            #expect(Arithmetic.evaluate(text) == nil, "\(text) should not evaluate")
        }
    }
}
