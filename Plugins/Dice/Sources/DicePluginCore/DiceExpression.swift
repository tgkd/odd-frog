import Foundation

/// Dice notation: `6d4+6`, `d20`, `d%`, `2d20kh1` (keep highest), `4d6kl3` (keep lowest),
/// `max(d20, d20)`, `+ - * /` and parentheses. `к` works as `d`: `2к6`.
public indirect enum DiceExpression: Sendable, Equatable {
    public enum Keep: Sendable, Equatable {
        case highest(Int)
        case lowest(Int)
    }
    public enum Operator: String, Sendable {
        case add = "+", subtract = "-", multiply = "*", divide = "/"
    }
    public enum Function: String, Sendable, CaseIterable {
        case max, min
    }
    case number(Int)
    case dice(count: Int, sides: Int, keep: Keep?)
    case negate(DiceExpression)
    case binary(Operator, DiceExpression, DiceExpression)
    case call(Function, [DiceExpression])
    case group(DiceExpression)

    public static let maxDice = 100
    public static let maxSides = 1_000
    public static let maxNumber = 1_000_000
    static let maxLength = 200

    /// Returns nil unless the whole text is an expression with at least one die, so plain arithmetic stays with the calculator.
    public static func parse(_ text: String) -> DiceExpression? {
        // The parser recurses on nesting, so the length cap also bounds the stack.
        guard text.count <= maxLength else {
            return nil
        }
        var parser = Parser(text)
        guard let expression = parser.expression(), parser.atEnd,
              (1...maxDice).contains(expression.diceCount) else {
            return nil
        }
        return expression
    }

    public var text: String {
        switch self {
        case .number(let value):
            return String(value)
        case .dice(let count, let sides, let keep):
            let prefix = count == 1 && keep == nil ? "" : String(count)
            let die = "\(prefix)d\(sides == 100 ? "%" : String(sides))"
            switch keep {
            case nil:
                return die
            case .highest(let kept):
                return "\(die)kh\(kept)"
            case .lowest(let kept):
                return "\(die)kl\(kept)"
            }
        case .negate(let inner):
            return "-\(inner.text)"
        case .binary(let op, let left, let right):
            return "\(left.text) \(op.rawValue) \(right.text)"
        case .call(let function, let arguments):
            return "\(function.rawValue)(\(arguments.map(\.text).joined(separator: ", ")))"
        case .group(let inner):
            return "(\(inner.text))"
        }
    }

    var diceCount: Int {
        switch self {
        case .number:
            return 0
        case .dice(let count, _, _):
            return count
        case .negate(let inner), .group(let inner):
            return inner.diceCount
        case .binary(_, let left, let right):
            return left.diceCount + right.diceCount
        case .call(_, let arguments):
            return arguments.reduce(0) { $0 + $1.diceCount }
        }
    }
}

private struct Parser {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text.lowercased()).filter { !$0.isWhitespace }
    }

    var atEnd: Bool {
        index == characters.count
    }

    mutating func expression() -> DiceExpression? {
        guard var left = term() else {
            return nil
        }
        while let op = take(.add, .subtract) {
            guard let right = term() else {
                return nil
            }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func term() -> DiceExpression? {
        guard var left = unary() else {
            return nil
        }
        while let op = take(.multiply, .divide) {
            guard let right = unary() else {
                return nil
            }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func unary() -> DiceExpression? {
        guard skip("-") else {
            return atom()
        }
        return unary().map(DiceExpression.negate)
    }

    private mutating func atom() -> DiceExpression? {
        if skip("(") {
            guard let inner = expression(), skip(")") else {
                return nil
            }
            return .group(inner)
        }
        if let function = DiceExpression.Function.allCases.first(where: { skip($0.rawValue + "(") }) {
            var arguments: [DiceExpression] = []
            repeat {
                guard let argument = expression() else {
                    return nil
                }
                arguments.append(argument)
            } while skip(",")
            guard skip(")") else {
                return nil
            }
            return .call(function, arguments)
        }
        let count = number()
        guard skip("d") || skip("к") else {
            return count.map(DiceExpression.number)
        }
        let sides = skip("%") ? 100 : number()
        guard let sides, (1...DiceExpression.maxSides).contains(sides) else {
            return nil
        }
        let dice = count ?? 1
        guard (1...DiceExpression.maxDice).contains(dice) else {
            return nil
        }
        guard skip("k") else {
            return .dice(count: dice, sides: sides, keep: nil)
        }
        let lowest = skip("l")
        if !lowest {
            _ = skip("h")
        }
        let kept = number() ?? 1
        guard (1...dice).contains(kept) else {
            return nil
        }
        return .dice(count: dice, sides: sides, keep: lowest ? .lowest(kept) : .highest(kept))
    }

    private mutating func number() -> Int? {
        var value: Int?
        while index < characters.count, let digit = characters[index].wholeNumberValue, characters[index].isASCII {
            let next = (value ?? 0) * 10 + digit
            guard next <= DiceExpression.maxNumber else {
                return nil
            }
            value = next
            index += 1
        }
        return value
    }

    private mutating func take(_ operators: DiceExpression.Operator...) -> DiceExpression.Operator? {
        operators.first { skip($0.rawValue) }
    }

    private mutating func skip(_ text: String) -> Bool {
        let expected = Array(text)
        guard characters[index...].starts(with: expected) else {
            return false
        }
        index += expected.count
        return true
    }
}
