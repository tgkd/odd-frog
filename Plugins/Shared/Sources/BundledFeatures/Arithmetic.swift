import Foundation

public enum Arithmetic {
    public static func evaluate(_ text: String) -> Double? {
        evaluateValue(text)?.scalar
    }

    static func evaluateValue(_ text: String, defaultCurrency: String? = nil) -> CalculatorValue? {
        guard text.count <= 4096, let tokens = tokenize(text, defaultCurrency: defaultCurrency) else { return nil }
        var parser = Parser(tokens: tokens, explicit: isScientificLiteral(text))
        guard let value = try? parser.parse(), parser.explicit else { return nil }
        return value
    }

    /// `2024-03`, `10/2023` and `1920x1080` evaluate, but they are just as likely a date or a file name.
    /// Only operators no name uses, or spaced ones, make the text plainly a calculation.
    public static func isPlainCalculation(_ text: String) -> Bool {
        if isScientificLiteral(text) { return true }
        if ["e", "pi", "π"].contains(text.trimmingCharacters(in: .whitespaces).lowercased()) { return true }
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if "+*×÷^%()".contains(character) { return true }
            guard "-−/".contains(character) else { continue }
            if index > 0, characters[index - 1].isWhitespace { return true }
            if index + 1 < characters.count, characters[index + 1].isWhitespace { return true }
        }
        return false
    }

    private static func isScientificLiteral(_ text: String) -> Bool {
        let literal = text.trimmingCharacters(in: .whitespaces).lowercased()
        return literal.contains("e") && scanNumber(Substring(literal), signed: true)?.rest.isEmpty == true
    }

    static func scanNumber(_ text: Substring, signed: Bool = false) -> (value: Double, rest: Substring)? {
        var index = text.startIndex
        if signed, index < text.endIndex, "+-−".contains(text[index]) { index = text.index(after: index) }
        var sawDigit = false
        var sawDot = false
        while index < text.endIndex {
            let character = text[index]
            if character.isASCII && character.isNumber { sawDigit = true }
            else if character == "." && !sawDot { sawDot = true }
            else { break }
            index = text.index(after: index)
        }
        guard sawDigit else { return nil }
        if index < text.endIndex, text[index] == "e" || text[index] == "E" {
            var end = text.index(after: index)
            if end < text.endIndex, "+-".contains(text[end]) { end = text.index(after: end) }
            let digits = end
            while end < text.endIndex, text[end].isASCII && text[end].isNumber { end = text.index(after: end) }
            if end > digits { index = end }
        }
        let literal = text[..<index].replacingOccurrences(of: "−", with: "-")
        guard let value = Double(literal), value.isFinite else { return nil }
        return (value, text[index...])
    }

    enum Token: Equatable {
        case number(Double)
        case money(Decimal, String)
        case word(String)
        case plus, minus, times, divide, power, percent, open, close, comma
    }

    static func tokenize(_ text: String, defaultCurrency: String? = nil) -> [Token]? {
        var tokens: [Token] = []
        var rest = Substring(text)
        while let first = rest.first {
            if first.isWhitespace { rest = rest.dropFirst(); continue }
            if CurrencyConversion.symbols[first] != nil {
                guard let currency = CurrencyConversion.currency(for: first, fallback: defaultCurrency?.uppercased()) else { return nil }
                rest = rest.dropFirst().drop(while: { $0.isWhitespace })
                guard let scanned = scanNumber(rest, signed: true),
                      let amount = Decimal(string: String(rest[..<scanned.rest.startIndex]), locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
                tokens.append(.money(amount, currency))
                rest = scanned.rest
                continue
            }
            if first == "." || (first.isASCII && first.isNumber) {
                let prefix = String(rest.prefix(2)).lowercased()
                if ["0x", "0b", "0o"].contains(prefix) {
                    let digits = rest.dropFirst(2).prefix { $0.isASCII && ($0.isNumber || $0.isLetter) }
                    guard !digits.isEmpty, let decimal = NumberRepresentation.convert(prefix + digits.lowercased(), to: 10),
                          let value = Double(decimal), value.isFinite else { return nil }
                    tokens.append(.number(value))
                    rest = rest.dropFirst(2 + digits.count)
                } else {
                    guard let scanned = scanNumber(rest), CalculatorValue.checked(scanned.value) != nil else { return nil }
                    tokens.append(.number(scanned.value))
                    rest = scanned.rest
                }
                continue
            }
            if first.isLetter || first == "°" {
                let candidate = rest.prefix { $0.isLetter || $0.isNumber || $0 == "/" || $0 == "°" }
                let word: Substring
                if UnitRegistry.unit(for: String(candidate)) != nil { word = candidate }
                else { word = rest.prefix { $0.isLetter || $0 == "°" } }
                guard !word.isEmpty else { return nil }
                rest = rest.dropFirst(word.count)
                if ["of", "x"].contains(word.lowercased()) { tokens.append(.times) }
                else { tokens.append(.word(String(word))) }
                continue
            }
            let token: Token
            switch first {
            case "+": token = .plus
            case "-", "−": token = .minus
            case "*", "×": token = .times
            case "/", "÷": token = .divide
            case "^": token = .power
            case "%": token = .percent
            case "(": token = .open
            case ")": token = .close
            case ",": token = .comma
            default: return nil
            }
            tokens.append(token)
            rest = rest.dropFirst()
        }
        return tokens.count <= 512 ? tokens : nil
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var explicit = false
        var depth = 0

        enum Failure: Error { case invalid }
        var current: Token? { index < tokens.count ? tokens[index] : nil }
        mutating func take(_ token: Token) -> Bool {
            guard current == token else { return false }
            index += 1
            return true
        }
        func require(_ value: CalculatorValue?) throws -> CalculatorValue {
            guard let value else { throw Failure.invalid }
            return value
        }
        mutating func parse() throws -> CalculatorValue {
            let value = try expression()
            guard index == tokens.count else { throw Failure.invalid }
            return value
        }
        mutating func expression() throws -> CalculatorValue {
            var left = try term()
            while let token = current, token == .plus || token == .minus {
                index += 1
                explicit = true
                let sign = token == .plus ? 1.0 : -1.0
                if let share = relativePercent() {
                    left = try require(left.scaled(by: 1 + sign * share))
                } else {
                    let right = try term()
                    left = try require(left.adding(right, sign: sign))
                }
            }
            return left
        }
        mutating func relativePercent() -> Double? {
            guard index + 1 < tokens.count, case .number(let value) = tokens[index], tokens[index + 1] == .percent else { return nil }
            let following = index + 2 < tokens.count ? tokens[index + 2] : nil
            if let following, ![Token.plus, .minus, .close, .comma].contains(following) { return nil }
            index += 2
            return value / 100
        }
        mutating func term() throws -> CalculatorValue {
            var left = try unary()
            while let token = current, token == .times || token == .divide {
                index += 1
                explicit = true
                let right = try unary()
                if let scalar = right.scalar {
                    guard token != .divide || scalar != 0 else { throw Failure.invalid }
                    left = try require(token == .divide ? left.divided(by: scalar) : left.scaled(by: scalar))
                } else if token == .times, let scalar = left.scalar {
                    left = try require(right.scaled(by: scalar))
                } else if token == .divide, case .quantity(let a) = left, case .quantity(let b) = right, let b = b.converted(to: a.unit), b.value != 0 {
                    left = try require(CalculatorValue.checked(a.value / b.value))
                } else { throw Failure.invalid }
            }
            return left
        }
        mutating func unary() throws -> CalculatorValue {
            guard depth < 16 else { throw Failure.invalid }
            depth += 1
            defer { depth -= 1 }
            if let token = current, token == .plus || token == .minus {
                index += 1
                let value = try unary()
                return try require(value.scaled(by: token == .minus ? -1 : 1))
            }
            let base = try postfix()
            if take(.power) {
                explicit = true
                let exponent = try unary()
                guard let a = base.scalar, let b = exponent.scalar else { throw Failure.invalid }
                return try require(CalculatorValue.checked(pow(a, b)))
            }
            return base
        }
        mutating func postfix() throws -> CalculatorValue {
            var value = try primary()
            while take(.percent) {
                explicit = true
                guard let scalar = value.scalar else { throw Failure.invalid }
                value = try require(CalculatorValue.checked(scalar / 100))
            }
            return value
        }
        mutating func primary() throws -> CalculatorValue {
            switch current {
            case .number(let number):
                index += 1
                if case .word(let word) = current, let unit = UnitRegistry.unit(for: word) {
                    index += 1
                    var quantity = CalculatorQuantity(value: number, unit: unit)
                    while unit is UnitDuration, index + 1 < tokens.count, case .number(let amount) = tokens[index], case .word(let name) = tokens[index + 1], let next = UnitRegistry.unit(for: name) as? UnitDuration {
                        guard let converted = CalculatorQuantity(value: amount, unit: next).converted(to: unit) else { throw Failure.invalid }
                        quantity = CalculatorQuantity(value: quantity.value + converted.value, unit: unit)
                        index += 2
                    }
                    return .quantity(quantity)
                }
                return .scalar(number)
            case .money(let amount, let currency):
                index += 1
                return .money(CalculatorMoney(amount: amount, currency: currency))
            case .word(let raw):
                index += 1
                let name = raw.lowercased()
                if name == "pi" || name == "π" { explicit = true; return .scalar(.pi) }
                if name == "e" { explicit = true; return .scalar(M_E) }
                guard take(.open) else { throw Failure.invalid }
                explicit = true
                var arguments = [try expression()]
                while take(.comma) { arguments.append(try expression()) }
                guard take(.close) else { throw Failure.invalid }
                return try function(name, arguments)
            case .open:
                index += 1
                let value = try expression()
                guard take(.close) else { throw Failure.invalid }
                return value
            default: throw Failure.invalid
            }
        }
        func function(_ name: String, _ arguments: [CalculatorValue]) throws -> CalculatorValue {
            guard let first = arguments.first else { throw Failure.invalid }
            switch name {
            case "sum", "avg":
                var result = first
                for argument in arguments.dropFirst() { result = try require(result.adding(argument)) }
                return name == "avg" ? try require(result.divided(by: Double(arguments.count))) : result
            case "min", "max":
                var result = first
                for argument in arguments.dropFirst() {
                    guard let order = argument.compared(to: result) else { throw Failure.invalid }
                    if order == (name == "min" ? .orderedAscending : .orderedDescending) { result = argument }
                }
                return result
            case "round":
                guard (1...2).contains(arguments.count), let value = first.scalar else { throw Failure.invalid }
                let places = arguments.count == 2 ? arguments[1].scalar : 0
                guard let places, places.rounded() == places, (-15...15).contains(places) else { throw Failure.invalid }
                let scale = pow(10, places)
                return try require(CalculatorValue.checked((value * scale).rounded() / scale))
            case "floor", "ceil", "abs", "sqrt":
                guard arguments.count == 1, let value = first.scalar else { throw Failure.invalid }
                let result: Double
                switch name {
                case "floor": result = floor(value)
                case "ceil": result = ceil(value)
                case "abs": result = abs(value)
                default: result = sqrt(value)
                }
                return try require(CalculatorValue.checked(result))
            default: throw Failure.invalid
            }
        }
    }
}
