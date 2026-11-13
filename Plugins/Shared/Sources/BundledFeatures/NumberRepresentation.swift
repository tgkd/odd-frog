import Foundation

enum NumberRepresentation {
    static func evaluate(_ text: String, locale: Locale) -> FormattedCalculation? {
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let separator = words.firstIndex(of: "nearest"), separator == 2, words[1] == "to", words.count == 4 {
            guard let value = Double(words[0]), value.isFinite else { return nil }
            let step = ["quarter": 0.25, "half": 0.5, "tenth": 0.1][words[3]] ?? Double(words[3])
            guard let step, step.isFinite, step > 0, let result = CalculatorValue.checked((value / step).rounded() * step) else { return nil }
            return result.formatted(input: text, locale: locale)
        }
        if words.count == 3, words[1] == "as", ["fraction", "improper", "mixed"].contains(words[2]) {
            return fraction(words[0], mixed: words[2] == "mixed", input: text)
        }
        if words.count >= 3, ["in", "to", "as"].contains(words[1]) {
            let radix: Int?
            if words.count == 4, words[2] == "base" { radix = Int(words[3]) }
            else if words.count == 3 { radix = ["hex": 16, "hexadecimal": 16, "binary": 2, "octal": 8, "decimal": 10][words[2]] }
            else { radix = nil }
            guard let radix, (2...36).contains(radix), let result = convert(words[0], to: radix) else { return nil }
            return FormattedCalculation(input: text, title: "\(result) (base \(radix))", copyText: result)
        }
        if words.count == 1 {
            let unsigned = words[0].drop(while: { $0 == "-" || $0 == "+" })
            if unsigned.hasPrefix("0x") || unsigned.hasPrefix("0b") || unsigned.hasPrefix("0o"), let result = convert(words[0], to: 10) {
                return FormattedCalculation(input: text, title: result)
            }
        }
        return nil
    }

    static func convert(_ literal: String, to radix: Int) -> String? {
        guard literal.count <= 1024 else { return nil }
        var literal = literal[...]
        let negative = literal.first == "-"
        if literal.first == "-" || literal.first == "+" { literal = literal.dropFirst() }
        var source = 10
        if let base = ["0x": 16, "0b": 2, "0o": 8][String(literal.prefix(2))] {
            source = base
            literal = literal.dropFirst(2)
        }
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        guard !literal.isEmpty else { return nil }
        var digits: [Int] = []
        for character in literal {
            guard let digit = alphabet.firstIndex(of: character), digit < source else { return nil }
            digits.append(digit)
        }
        var result: [Character] = []
        while !digits.isEmpty {
            var quotient: [Int] = []
            var remainder = 0
            for digit in digits {
                let value = remainder * source + digit
                let next = value / radix
                remainder = value % radix
                if !quotient.isEmpty || next != 0 { quotient.append(next) }
            }
            result.append(alphabet[remainder])
            digits = quotient
        }
        let output = String(result.reversed())
        return (negative && output != "0" ? "-" : "") + output
    }

    private static func fraction(_ literal: String, mixed: Bool, input: String) -> FormattedCalculation? {
        var literal = literal[...]
        let negative = literal.first == "-"
        if literal.first == "-" || literal.first == "+" { literal = literal.dropFirst() }
        let parts = literal.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), literal.contains(where: { $0.isNumber }),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let numerator = UInt64(parts.joined()), parts.count == 1 || parts[1].count <= 18 else { return nil }
        var denominator: UInt64 = 1
        if parts.count == 2 { for _ in parts[1] { denominator *= 10 } }
        var a = numerator
        var b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        let top = numerator / a
        let bottom = denominator / a
        let sign = negative && top != 0 ? "-" : ""
        let result: String
        if bottom == 1 { result = "\(sign)\(top)" }
        else if mixed && top >= bottom { result = "\(sign)\(top / bottom) \(top % bottom)/\(bottom)" }
        else { result = "\(sign)\(top)/\(bottom)" }
        return FormattedCalculation(input: input, title: result)
    }
}
