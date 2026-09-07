import Foundation

public enum Arithmetic {
    public static func evaluate(_ text: String) -> Double? {
        guard let tokens = tokenize(text) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = try? parser.parse(), parser.usedOperator, value.isFinite else { return nil }
        return value
    }

    static func scanNumber(_ text: Substring) -> (value: Double, rest: Substring)? {
        var index = text.startIndex
        var sawDigit = false
        var sawDot = false
        while index < text.endIndex {
            let character = text[index]
            if character.isASCII, character.isNumber {
                sawDigit = true
            } else if character == ".", !sawDot {
                sawDot = true
            } else {
                break
            }
            index = text.index(after: index)
        }
        guard sawDigit else { return nil }
        var literal = text[text.startIndex..<index]
        if literal.hasSuffix(".") { literal = literal.dropLast() }
        guard let value = Double(literal) else { return nil }
        return (value, text[index...])
    }

    enum Token: Equatable {
        case number(Double)
        case plus
        case minus
        case times
        case divide
        case power
        case percent
        case open
        case close
    }

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var rest = Substring(text)
        while let first = rest.first {
            if first.isWhitespace {
                rest = rest.dropFirst()
                continue
            }
            if first == "." || (first.isASCII && first.isNumber) {
                guard let scanned = scanNumber(rest) else { return nil }
                tokens.append(.number(scanned.value))
                rest = scanned.rest
                continue
            }
            if first.isLetter {
                let word = rest.prefix { $0.isLetter }
                rest = rest.dropFirst(word.count)
                let lowered = word.lowercased()
                guard lowered == "of" || lowered == "x", endsOperand(tokens.last) else { return nil }
                tokens.append(.times)
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
            default: return nil
            }
            tokens.append(token)
            rest = rest.dropFirst()
        }
        return tokens
    }

    private static func endsOperand(_ token: Token?) -> Bool {
        switch token {
        case .number, .close, .percent: true
        default: false
        }
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var usedOperator = false
        private var depth = 0

        private enum Failure: Error {
            case invalid
        }

        private var current: Token? {
            index < tokens.count ? tokens[index] : nil
        }

        mutating func parse() throws -> Double {
            let value = try expression()
            guard index == tokens.count else { throw Failure.invalid }
            return value
        }

        private mutating func expression() throws -> Double {
            var left = try term()
            while let token = current, token == .plus || token == .minus {
                index += 1
                usedOperator = true
                if let share = relativePercent() {
                    left += token == .plus ? left * share : -(left * share)
                    continue
                }
                let right = try term()
                left = token == .plus ? left + right : left - right
            }
            return left
        }

        private mutating func relativePercent() -> Double? {
            guard index + 1 < tokens.count, case .number(let value) = tokens[index], tokens[index + 1] == .percent else { return nil }
            let following = index + 2 < tokens.count ? tokens[index + 2] : nil
            if let following, following != .plus, following != .minus, following != .close { return nil }
            index += 2
            return value / 100
        }

        private mutating func term() throws -> Double {
            var left = try unary()
            while let token = current, token == .times || token == .divide {
                index += 1
                usedOperator = true
                let right = try unary()
                if token == .divide {
                    guard right != 0 else { throw Failure.invalid }
                    left /= right
                } else {
                    left *= right
                }
            }
            return left
        }

        private mutating func unary() throws -> Double {
            if let token = current, token == .plus || token == .minus {
                index += 1
                let value = try unary()
                return token == .minus ? -value : value
            }
            return try power()
        }

        private mutating func power() throws -> Double {
            let base = try postfix()
            guard current == .power else { return base }
            index += 1
            usedOperator = true
            let exponent = try unary()
            return pow(base, exponent)
        }

        private mutating func postfix() throws -> Double {
            var value = try primary()
            while current == .percent {
                index += 1
                usedOperator = true
                value /= 100
            }
            return value
        }

        private mutating func primary() throws -> Double {
            switch current {
            case .number(let value):
                index += 1
                return value
            case .open:
                guard depth < 64 else { throw Failure.invalid }
                index += 1
                depth += 1
                let value = try expression()
                depth -= 1
                guard current == .close else { throw Failure.invalid }
                index += 1
                return value
            default:
                throw Failure.invalid
            }
        }
    }
}
