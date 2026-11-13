import Foundation

enum DomainCalculation {
    static func evaluate(_ input: String, defaultCurrency: String?, locale: Locale) -> FormattedCalculation? {
        let text = input.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if let money = money(text, defaultCurrency: defaultCurrency, locale: locale) { return money }
        if text.lowercased().hasPrefix("transfer "), let separator = text.range(of: " at ", options: .caseInsensitive) {
            guard let size = quantity(String(text[text.index(text.startIndex, offsetBy: 9)..<separator.lowerBound])),
                  let rate = quantity(String(text[separator.upperBound...])),
                  let bits = size.converted(to: UnitInformationStorage.bits), rate.unit is DataRateUnit,
                  let bps = rate.converted(to: DataRateUnit.baseUnit()), bits.value >= 0, bps.value > 0 else { return nil }
            let seconds = bits.value / bps.value
            guard seconds.isFinite, seconds < 1e15 else { return nil }
            let title = seconds.rounded() == seconds ? TemporalCalc.Evaluator.elapsedText(seconds) : "\(CalculatorFormat.number(seconds, locale: locale)) s"
            return FormattedCalculation(input: input, title: title, kindLabel: "Time")
        }
        for separator in [" in ", " to ", " as "] {
            guard let range = text.range(of: separator, options: .caseInsensitive) else { continue }
            let source = String(text[..<range.lowerBound])
            let target = String(text[range.upperBound...])
            let constants: [String: CalculatorQuantity] = [
                "speed of light": CalculatorQuantity(value: 299_792_458, unit: UnitSpeed.metersPerSecond),
                "c": CalculatorQuantity(value: 299_792_458, unit: UnitSpeed.metersPerSecond),
                "standard gravity": CalculatorQuantity(value: 9.80665, unit: UnitAcceleration.metersPerSecondSquared),
                "standard atmosphere": CalculatorQuantity(value: 101_325, unit: UnitPressure.newtonsPerMetersSquared),
                "absolute zero": CalculatorQuantity(value: 0, unit: UnitTemperature.kelvin)
            ]
            if let constant = constants[source.lowercased()], let unit = UnitRegistry.unit(for: target), let result = constant.converted(to: unit) {
                return CalculatorValue.quantity(result).formatted(input: input, locale: locale)
            }
            if let pace = pace(source), let unit = UnitRegistry.unit(for: target) as? UnitSpeed {
                guard let speed = CalculatorQuantity(value: pace.meters / pace.seconds, unit: UnitSpeed.metersPerSecond).converted(to: unit) else { return nil }
                return CalculatorValue.quantity(speed).formatted(input: input, locale: locale)
            }
            if let distance = paceDistance(target), let quantity = quantity(source), let speed = quantity.converted(to: UnitSpeed.metersPerSecond), speed.value > 0 {
                let seconds = distance / speed.value
                guard seconds.isFinite, seconds < 1e12 else { return nil }
                let rounded = seconds.rounded()
                let title = "\(Int(rounded) / 60):\(String(format: "%02d", Int(rounded) % 60)) \(target.lowercased())"
                return FormattedCalculation(input: input, title: title, kindLabel: "Units")
            }
        }
        return nil
    }

    static func quantity(_ text: String) -> CalculatorQuantity? {
        guard let scanned = Arithmetic.scanNumber(Substring(text), signed: true),
              let unit = UnitRegistry.unit(for: scanned.rest.trimmingCharacters(in: .whitespaces)) else { return nil }
        return CalculatorQuantity(value: scanned.value, unit: unit)
    }

    private static func paceDistance(_ text: String) -> Double? {
        switch text.lowercased() {
        case "min/km": 1000
        case "min/mi": 1609.344
        default: nil
        }
    }

    private static func pace(_ text: String) -> (seconds: Double, meters: Double)? {
        let words = text.split(separator: " ")
        guard words.count == 2, let meters = paceDistance(String(words[1])) else { return nil }
        let clock = words[0].split(separator: ":", omittingEmptySubsequences: false)
        let seconds: Double
        if clock.count == 2, let minutes = Double(clock[0]), minutes >= 0, minutes.rounded() == minutes,
           let rest = Double(clock[1]), (0..<60).contains(rest) { seconds = minutes * 60 + rest }
        else if clock.count == 1, let minutes = Double(clock[0]) { seconds = minutes * 60 }
        else { return nil }
        guard seconds.isFinite, seconds > 0 else { return nil }
        return (seconds, meters)
    }

    private static func money(_ text: String, defaultCurrency: String?, locale: Locale) -> FormattedCalculation? {
        var body = text
        var people: Int?
        if let split = body.range(of: " split ", options: .caseInsensitive) {
            guard let count = Int(body[split.upperBound...]), (1...1_000_000).contains(count) else { return nil }
            people = count
            body = String(body[..<split.lowerBound])
        }
        if let people {
            let amount: CalculatorMoney?
            if let literal = moneyLiteral(body, defaultCurrency: defaultCurrency) { amount = literal }
            else if case .money(let value) = Arithmetic.evaluateValue(body, defaultCurrency: defaultCurrency) { amount = value }
            else { amount = nil }
            if let amount {
                guard amount.amount >= 0, let each = split(amount, among: people) else { return nil }
                return FormattedCalculation(input: text, title: "\(each.text(locale: locale)) each", copyText: each.number(locale: locale, copy: true), kindLabel: "Currency")
            }
        }
        guard let percent = body.firstIndex(of: "%"), let rate = Decimal(string: String(body[..<percent]), locale: Locale(identifier: "en_US_POSIX")),
              !rate.isNaN, rate >= 0,
              let scanned = Arithmetic.scanNumber(body[..<percent], signed: true), scanned.rest.isEmpty else { return nil }
        var tail = String(body[body.index(after: percent)...]).trimmingCharacters(in: .whitespaces)
        let operation: String
        if tail.lowercased().hasPrefix("tip on ") { operation = "tip"; tail = String(tail.dropFirst(7)) }
        else if tail.lowercased().hasPrefix("vat in ") { operation = "inclusive"; tail = String(tail.dropFirst(7)) }
        else if tail.lowercased().hasPrefix("vat on ") { operation = "exclusive"; tail = String(tail.dropFirst(7)) }
        else if tail.lowercased().hasPrefix("off ") { operation = "discount"; tail = String(tail.dropFirst(4)) }
        else { return nil }
        guard let amount = moneyLiteral(tail, defaultCurrency: defaultCurrency), amount.amount >= 0 else { return nil }
        let share = rate / 100
        var title: String
        var copy: CalculatorMoney
        let bill: CalculatorMoney
        if operation == "tip" || operation == "exclusive" {
            guard let extra = amount.scaled(by: share), let total = amount.scaled(by: 1 + share) else { return nil }
            title = "\(operation == "tip" ? "Tip" : "VAT") \(extra.text(locale: locale)) · Total \(total.text(locale: locale))"
            copy = extra
            bill = total
        } else if operation == "inclusive" {
            guard let net = amount.scaled(by: 1 / (1 + share)) else { return nil }
            let tax = CalculatorMoney(amount: amount.amount - net.amount, currency: amount.currency)
            title = "VAT \(tax.text(locale: locale)) · Net \(net.text(locale: locale))"
            copy = tax
            bill = amount
        } else {
            guard rate <= 100, let discounted = amount.scaled(by: 1 - share) else { return nil }
            title = discounted.text(locale: locale)
            copy = discounted
            bill = discounted
        }
        if let people {
            guard let each = split(bill, among: people) else { return nil }
            title = operation == "discount" ? "\(each.text(locale: locale)) each" : "\(title) · \(each.text(locale: locale)) each"
            copy = each
        }
        return FormattedCalculation(input: text, title: title, copyText: copy.number(locale: locale, copy: true), kindLabel: "Currency")
    }

    private static func split(_ amount: CalculatorMoney, among people: Int) -> CalculatorMoney? {
        let value = amount.amount / Decimal(people)
        return value.isNaN ? nil : CalculatorMoney(amount: value, currency: amount.currency)
    }

    private static func moneyLiteral(_ text: String, defaultCurrency: String?) -> CalculatorMoney? {
        var rest = Substring(text)
        var currency = ""
        if let first = rest.first, let code = CurrencyConversion.currency(for: first, fallback: defaultCurrency?.uppercased()) {
            currency = code
            rest = rest.dropFirst().drop(while: { $0.isWhitespace })
        }
        guard let number = Arithmetic.scanNumber(rest, signed: true),
              let amount = Decimal(string: String(rest[..<number.rest.startIndex]), locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
        let suffix = number.rest.trimmingCharacters(in: .whitespaces).uppercased()
        if !suffix.isEmpty {
            guard currency.isEmpty, Locale.commonISOCurrencyCodes.contains(suffix) else { return nil }
            currency = suffix
        }
        return CalculatorMoney(amount: amount, currency: currency)
    }
}
