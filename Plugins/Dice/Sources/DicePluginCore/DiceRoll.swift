import Foundation

public struct DiceRoll: Sendable, Equatable {
    public var total: Int
    /// The expression with every die replaced by its faces, like `[3, 1, 4] + 6`; dropped faces are struck through.
    public var breakdown: String
}

public extension DiceExpression {
    /// `die` returns a face from 1 to the given number of sides. Returns nil on division by zero or overflow.
    func roll(_ die: (Int) -> Int) -> DiceRoll? {
        switch self {
        case .number(let value):
            return DiceRoll(total: value, breakdown: String(value))
        case .dice(let count, let sides, let keep):
            let faces = (0..<count).map { _ in die(sides) }
            let kept = Self.kept(faces, keep)
            let shown = faces.indices.map { kept.contains($0) ? String(faces[$0]) : Self.struck(String(faces[$0])) }
            return DiceRoll(total: kept.reduce(0) { $0 + faces[$1] }, breakdown: "[\(shown.joined(separator: ", "))]")
        case .negate(let inner):
            guard let value = inner.roll(die), let total = Self.apply(.subtract, 0, value.total) else {
                return nil
            }
            return DiceRoll(total: total, breakdown: "-\(value.breakdown)")
        case .binary(let op, let left, let right):
            guard let left = left.roll(die), let right = right.roll(die),
                  let total = Self.apply(op, left.total, right.total) else {
                return nil
            }
            return DiceRoll(total: total, breakdown: "\(left.breakdown) \(op.rawValue) \(right.breakdown)")
        case .call(let function, let arguments):
            var rolls: [DiceRoll] = []
            for argument in arguments {
                guard let value = argument.roll(die) else {
                    return nil
                }
                rolls.append(value)
            }
            let totals = rolls.map(\.total)
            let total = function == .max ? totals.max() : totals.min()
            return total.map {
                DiceRoll(total: $0, breakdown: "\(function.rawValue)(\(rolls.map(\.breakdown).joined(separator: ", ")))")
            }
        case .group(let inner):
            return inner.roll(die).map { DiceRoll(total: $0.total, breakdown: "(\($0.breakdown))") }
        }
    }

    private static func kept(_ faces: [Int], _ keep: Keep?) -> Set<Int> {
        let ranked = faces.indices.sorted { faces[$0] > faces[$1] }
        switch keep {
        case nil:
            return Set(faces.indices)
        case .highest(let count):
            return Set(ranked.prefix(count))
        case .lowest(let count):
            return Set(ranked.reversed().prefix(count))
        }
    }

    private static func struck(_ text: String) -> String {
        text.map { "\($0)\u{0336}" }.joined()
    }

    private static func apply(_ op: Operator, _ left: Int, _ right: Int) -> Int? {
        let result: (partialValue: Int, overflow: Bool)
        switch op {
        case .add:
            result = left.addingReportingOverflow(right)
        case .subtract:
            result = left.subtractingReportingOverflow(right)
        case .multiply:
            result = left.multipliedReportingOverflow(by: right)
        case .divide:
            guard right != 0 else {
                return nil
            }
            let (quotient, overflow) = left.dividedReportingOverflow(by: right)
            guard !overflow else {
                return nil
            }
            // Tabletop rules round down, so -7 / 2 is -4, not Swift's -3.
            return left % right != 0 && (left < 0) != (right < 0) ? quotient - 1 : quotient
        }
        return result.overflow ? nil : result.partialValue
    }
}
