import Foundation

struct CalculatorQuantity {
    let value: Double
    let unit: Dimension

    func converted(to target: Dimension) -> CalculatorQuantity? {
        guard type(of: unit).baseUnit() == type(of: target).baseUnit() else { return nil }
        let result = Measurement(value: value, unit: unit).converted(to: target).value
        return result.isFinite ? CalculatorQuantity(value: result, unit: target) : nil
    }
}

struct CalculatorMoney {
    let amount: Decimal
    let currency: String

    func scaled(by factor: Decimal) -> CalculatorMoney? {
        let result = amount * factor
        return result.isNaN ? nil : CalculatorMoney(amount: result, currency: currency)
    }

    func number(locale: Locale, copy: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = !copy
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? amount.description
    }

    func text(locale: Locale) -> String {
        let number = number(locale: locale)
        return currency.isEmpty ? number : "\(number) \(currency)"
    }
}

enum CalculatorValue {
    case scalar(Double)
    case quantity(CalculatorQuantity)
    case money(CalculatorMoney)

    var scalar: Double? {
        if case .scalar(let value) = self { value } else { nil }
    }

    func scaled(by factor: Double) -> CalculatorValue? {
        guard factor.isFinite else { return nil }
        switch self {
        case .scalar(let value): return Self.checked(value * factor)
        case .quantity(let quantity):
            guard !(quantity.unit is UnitTemperature), (quantity.value * factor).isFinite else { return nil }
            return .quantity(CalculatorQuantity(value: quantity.value * factor, unit: quantity.unit))
        case .money(let money):
            guard let decimal = Decimal(string: String(factor), locale: Locale(identifier: "en_US_POSIX")), let result = money.scaled(by: decimal) else { return nil }
            return .money(result)
        }
    }

    func divided(by divisor: Double) -> CalculatorValue? {
        guard divisor.isFinite, divisor != 0 else { return nil }
        switch self {
        case .scalar(let value): return Self.checked(value / divisor)
        case .quantity(let quantity):
            guard !(quantity.unit is UnitTemperature), (quantity.value / divisor).isFinite else { return nil }
            return .quantity(CalculatorQuantity(value: quantity.value / divisor, unit: quantity.unit))
        case .money(let money):
            guard let decimal = Decimal(string: String(divisor), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            let result = money.amount / decimal
            return result.isNaN ? nil : .money(CalculatorMoney(amount: result, currency: money.currency))
        }
    }

    func adding(_ other: CalculatorValue, sign: Double = 1) -> CalculatorValue? {
        switch (self, other) {
        case (.scalar(let a), .scalar(let b)): return Self.checked(a + sign * b)
        case (.quantity(let a), .quantity(let b)):
            guard !(a.unit is UnitTemperature), let b = b.converted(to: a.unit), (a.value + sign * b.value).isFinite else { return nil }
            return .quantity(CalculatorQuantity(value: a.value + sign * b.value, unit: a.unit))
        case (.money(let a), .money(let b)):
            guard a.currency == b.currency else { return nil }
            let amount = a.amount + (sign == 1 ? b.amount : -b.amount)
            return amount.isNaN ? nil : .money(CalculatorMoney(amount: amount, currency: a.currency))
        default: return nil
        }
    }

    func compared(to other: CalculatorValue) -> ComparisonResult? {
        let left: Double
        let right: Double
        switch (self, other) {
        case (.scalar(let a), .scalar(let b)): (left, right) = (a, b)
        case (.quantity(let a), .quantity(let b)):
            guard let converted = b.converted(to: a.unit) else { return nil }
            (left, right) = (a.value, converted.value)
        case (.money(let a), .money(let b)):
            guard a.currency == b.currency else { return nil }
            return a.amount == b.amount ? .orderedSame : (a.amount < b.amount ? .orderedAscending : .orderedDescending)
        default: return nil
        }
        return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    }

    static func checked(_ value: Double) -> CalculatorValue? {
        guard value.isFinite else { return nil }
        return .scalar(value)
    }

    func formatted(input: String, locale: Locale) -> FormattedCalculation {
        switch self {
        case .scalar(let value):
            return FormattedCalculation(input: input, title: CalculatorFormat.number(value, locale: locale), copyText: CalculatorFormat.number(value, locale: locale, copy: true))
        case .quantity(let quantity):
            return FormattedCalculation(input: input, title: UnitConversion.format(quantity.value, unit: quantity.unit, locale: locale), copyText: "\(CalculatorFormat.number(quantity.value, locale: locale, copy: true)) \(quantity.unit.symbol)", kindLabel: "Units")
        case .money(let money):
            return FormattedCalculation(input: input, title: money.text(locale: locale), copyText: money.number(locale: locale, copy: true), kindLabel: "Currency")
        }
    }
}
