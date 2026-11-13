import Foundation

public enum CalculatorFormat {
    public static func number(_ value: Double, locale: Locale, decimals: Int = 6, copy: Bool = false) -> String {
        let magnitude = abs(value)
        if value.rounded() == value, magnitude <= 9_007_199_254_740_991 {
            return value.formatted(.number.grouping(copy ? .never : .automatic).precision(.fractionLength(0)).locale(locale))
        }
        if magnitude != 0 && (magnitude < pow(10, -Double(decimals)) || magnitude >= 1e15) {
            return value.formatted(.number.notation(.scientific).grouping(.never).precision(.significantDigits(1...(copy ? 15 : 12))).locale(locale))
        }
        if copy {
            return value.formatted(.number.grouping(.never).precision(.significantDigits(1...15)).locale(locale))
        }
        return value.formatted(.number.precision(.fractionLength(0...decimals)).locale(locale))
    }
    static func currency(_ value: Double, locale: Locale, copy: Bool = false) -> String {
        if value != 0 && abs(value) < 0.005 { return number(value, locale: locale, decimals: 2, copy: copy) }
        return value.formatted(.number.grouping(copy ? .never : .automatic).precision(.fractionLength(2)).locale(locale))
    }
}

public struct FormattedCalculation: Sendable, Hashable {
    public let input: String
    public let title: String
    public let copyText: String
    public let kindLabel: String

    init(input: String, title: String, copyText: String? = nil, kindLabel: String = "Calculator") {
        self.input = input
        self.title = title
        self.copyText = copyText ?? title
        self.kindLabel = kindLabel
    }
}
