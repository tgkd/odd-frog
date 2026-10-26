import Foundation
import OddFrogCore

public struct CurrencyConversion: Sendable, Hashable {
    public let input: String
    public let value: Double
    public let result: String
    public let updated: Date

    public init(input: String, value: Double, result: String, updated: Date) {
        self.input = input
        self.value = value
        self.result = result
        self.updated = updated
    }

    static let keywords: Set<String> = ["in", "to", "as"]

    static let symbols: [Character: String] = [
        "$": "USD",
        "€": "EUR",
        "£": "GBP",
        "¥": "JPY",
        "₽": "RUB",
        "₴": "UAH",
        "₺": "TRY",
        "₹": "INR",
        "₩": "KRW",
    ]

    static let sharedSymbols: [Character: Set<String>] = [
        "$": ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN", "ARS", "CLP", "COP"],
        "¥": ["JPY", "CNY"],
    ]

    static let wordLikeCodes: Set<String> = ["all", "bam", "bob", "cop", "cup", "gel", "kid", "mad", "mop", "pen", "sos", "top", "try"]

    public static func evaluate(_ text: String, rates: CurrencyRates, defaultCurrency: String? = nil, locale: Locale = .current) -> CurrencyConversion? {
        let fallback = defaultCurrency.flatMap { code($0, rates: rates) }
        var head = Substring(text.trimmingCharacters(in: .whitespaces))
        var symbolCode: String?
        if let first = head.first, let code = currency(for: first, fallback: fallback) {
            symbolCode = code
            head = head.dropFirst()
        }
        guard let scanned = Arithmetic.scanNumber(head.drop(while: { $0.isWhitespace })) else { return nil }
        let literal = String(head[head.startIndex..<scanned.rest.startIndex]).trimmingCharacters(in: .whitespaces)
        var tail = scanned.rest
        if symbolCode == nil, let first = tail.first, let code = currency(for: first, fallback: fallback) {
            symbolCode = code
            tail = tail.dropFirst()
        }
        var normalized = String(tail).lowercased()
        for separator in ["->", "→", "="] {
            normalized = normalized.replacingOccurrences(of: separator, with: " in ")
        }
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let sourceToken: String
        let targetToken: String?
        if let symbolCode {
            sourceToken = symbolCode
            if tokens.isEmpty {
                targetToken = nil
            } else if tokens.count == 2, keywords.contains(tokens[0]) {
                targetToken = tokens[1]
            } else if tokens.count == 1, !keywords.contains(tokens[0]) {
                targetToken = tokens[0]
            } else {
                return nil
            }
        } else if tokens.count == 3, keywords.contains(tokens[1]) {
            sourceToken = tokens[0]
            targetToken = tokens[2]
        } else if tokens.count == 2, !keywords.contains(tokens[1]) {
            sourceToken = tokens[0]
            targetToken = tokens[1]
        } else if tokens.count == 1, !keywords.contains(tokens[0]), !wordLikeCodes.contains(tokens[0]), UnitRegistry.unit(for: tokens[0]) == nil {
            sourceToken = tokens[0]
            targetToken = nil
        } else {
            return nil
        }
        let target: String?
        if let targetToken {
            target = code(targetToken, rates: rates)
        } else {
            target = fallback
        }
        guard let source = code(sourceToken, rates: rates), let target else { return nil }
        guard targetToken != nil || source != target else { return nil }
        guard let value = rates.convert(scanned.value, from: source, to: target) else { return nil }
        return CurrencyConversion(
            input: "\(literal) \(source) → \(target)",
            value: value,
            result: "\(value.formatted(.number.precision(.fractionLength(2)).locale(locale))) \(target)",
            updated: rates.timestamp
        )
    }

    private static func currency(for symbol: Character, fallback: String?) -> String? {
        if let fallback, sharedSymbols[symbol]?.contains(fallback) == true {
            return fallback
        }
        return symbols[symbol]
    }

    private static func code(_ token: String, rates: CurrencyRates) -> String? {
        guard token.count == 3, token.allSatisfy({ $0.isLetter }) else { return nil }
        let upper = token.uppercased()
        guard rates.rates[upper] != nil else { return nil }
        return upper
    }
}
