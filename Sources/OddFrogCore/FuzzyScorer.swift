import Foundation

public enum FuzzyScorer {
    static let matchScore = 16
    static let prefixBonus = 10
    static let boundaryBonus = 12
    static let camelBonus = 7
    static let consecutiveBonus = 8
    static let gapStartPenalty = 3
    static let gapExtendPenalty = 1
    static let maxCandidateLength = 96

    public static func maxScore(queryLength: Int) -> Int {
        guard queryLength > 0 else { return 0 }
        return matchScore * queryLength + prefixBonus + boundaryBonus + consecutiveBonus * (queryLength - 1)
    }

    public static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.lowercased().unicodeScalars)
        guard !q.isEmpty else { return nil }
        let original = Array(candidate.unicodeScalars.prefix(maxCandidateLength))
        let c = Array(candidate.lowercased().unicodeScalars.prefix(maxCandidateLength))
        guard c.count == original.count, q.count <= c.count else { return nil }

        let bonuses = positionBonuses(original)
        let none = Int.min / 4
        var previous = [Int](repeating: none, count: c.count)

        for j in 0..<c.count where c[j] == q[0] {
            previous[j] = matchScore + bonuses[j]
        }
        if !previous.contains(where: { $0 != none }) { return nil }

        for i in 1..<q.count {
            var current = [Int](repeating: none, count: c.count)
            var bestGapped = none
            for j in 0..<c.count {
                if j >= 2, previous[j - 2] != none {
                    bestGapped = max(bestGapped, previous[j - 2] + (j - 2))
                }
                guard c[j] == q[i] else { continue }
                var best = none
                if j >= 1, previous[j - 1] != none {
                    best = previous[j - 1] + consecutiveBonus
                }
                if bestGapped != none {
                    let gapped = bestGapped - j + 1 - gapStartPenalty + gapExtendPenalty
                    best = max(best, gapped)
                }
                if best != none {
                    current[j] = best + matchScore + bonuses[j]
                }
            }
            if !current.contains(where: { $0 != none }) { return nil }
            previous = current
        }
        return previous.filter { $0 != none }.max()
    }

    public static func normalized(query: String, candidate: String) -> Double? {
        guard let raw = score(query: query, candidate: candidate) else { return nil }
        let max = Double(maxScore(queryLength: query.unicodeScalars.count))
        guard max > 0 else { return nil }
        return Swift.min(100, Swift.max(0, Double(raw) / max * 100))
    }

    private static func positionBonuses(_ scalars: [Unicode.Scalar]) -> [Int] {
        var out = [Int](repeating: 0, count: scalars.count)
        for j in 0..<scalars.count {
            if j == 0 {
                out[j] = prefixBonus + boundaryBonus
                continue
            }
            let prev = scalars[j - 1]
            let cur = scalars[j]
            if isSeparator(prev) {
                out[j] = boundaryBonus
            } else if isLower(prev), isUpper(cur) {
                out[j] = camelBonus
            }
        }
        return out
    }

    private static func isSeparator(_ s: Unicode.Scalar) -> Bool {
        switch s {
        case " ", "-", "_", ".", "/", ":", "(", ")": true
        default: false
        }
    }

    private static func isLower(_ s: Unicode.Scalar) -> Bool { s.properties.isLowercase }
    private static func isUpper(_ s: Unicode.Scalar) -> Bool { s.properties.isUppercase }
}
