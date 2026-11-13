import Foundation
import OddFrogCore

public struct UnitConversion: Sendable, Hashable {
    public let input: String
    public let value: Double
    public let result: String

    public init(input: String, value: Double, result: String) {
        self.input = input
        self.value = value
        self.result = result
    }

    static let keywords: Set<String> = ["in", "to", "as"]

    static func style(locale: Locale) -> Measurement<Dimension>.FormatStyle {
        Measurement<Dimension>.FormatStyle(
            width: .abbreviated,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...4)).locale(locale)
        )
    }

    static func format(_ value: Double, unit: Dimension, locale: Locale) -> String {
        if value != 0 && (abs(value) < 0.0001 || abs(value) >= 1e15) || unit is DataRateUnit {
            return "\(CalculatorFormat.number(value, locale: locale, decimals: 4)) \(unit.symbol)"
        }
        return Measurement(value: value, unit: unit).formatted(style(locale: locale))
    }

    public static func evaluate(_ text: String, locale: Locale = .current) -> UnitConversion? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let scanned = Arithmetic.scanNumber(Substring(trimmed), signed: true) else { return nil }
        let literal = String(trimmed[trimmed.startIndex..<scanned.rest.startIndex])
        var tail = String(scanned.rest)
        for separator in ["->", "→", "="] {
            tail = tail.replacingOccurrences(of: separator, with: " in ")
        }
        let tokens = tail.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let sourceToken: String
        let targetToken: String
        if tokens.count == 3, keywords.contains(tokens[1].lowercased()) {
            sourceToken = tokens[0]
            targetToken = tokens[2]
        } else if tokens.count == 2, !keywords.contains(tokens[1].lowercased()) {
            sourceToken = tokens[0]
            targetToken = tokens[1]
        } else {
            return nil
        }
        guard let source = UnitRegistry.unit(for: sourceToken), let target = UnitRegistry.unit(for: targetToken) else { return nil }
        guard type(of: source).baseUnit() == type(of: target).baseUnit() else { return nil }
        let converted = Measurement(value: scanned.value, unit: source).converted(to: target)
        guard converted.value.isFinite else { return nil }
        return UnitConversion(
            input: "\(literal) \(source.symbol) → \(target.symbol)",
            value: converted.value,
            result: format(converted.value, unit: target, locale: locale)
        )
    }
}
