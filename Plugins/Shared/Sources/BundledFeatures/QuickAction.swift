import Foundation
import OddFrogCore

public enum CalculationKind: Sendable, Hashable {
    case arithmetic
    case measurement(result: String)
    case currency(result: String, updated: Date)
}

public enum QuickAction: Sendable, Hashable {
    case openURL(URL)
    case webSearch(query: String, url: URL)
    case terminal(String)
    case calculation(input: String, value: Double, kind: CalculationKind, locale: Locale)
    case temporal(TemporalCalculation)

    public var id: String {
        switch self {
        case .openURL(let url): "quick:url:\(url.absoluteString)"
        case .webSearch(let query, _): "quick:search:\(query)"
        case .terminal(let text): "quick:terminal:\(text)"
        case .calculation(let input, _, _, _): "quick:calc:\(input)"
        case .temporal(let calculation): "quick:calc:\(calculation.input)"
        }
    }

    public var title: String {
        switch self {
        case .openURL(let url): "Open \(Self.displayHostPath(url))"
        case .webSearch(let query, _): "Search for “\(query)”"
        case .terminal: "Run in Terminal"
        case .calculation(_, let value, let kind, let locale): Self.title(value: value, kind: kind, locale: locale)
        case .temporal(let calculation): calculation.title
        }
    }

    public var subtitle: String? {
        switch self {
        case .openURL: nil
        case .webSearch(_, let url): url.host
        case .terminal(let text): text
        case .calculation(let input, _, let kind, let locale): Self.subtitle(input: input, kind: kind, locale: locale)
        case .temporal(let calculation): calculation.subtitle
        }
    }

    public var answersQuery: Bool {
        switch self {
        case .openURL, .webSearch, .terminal: false
        case .calculation(let input, _, let kind, _):
            if case .arithmetic = kind { Arithmetic.isPlainCalculation(input) } else { true }
        case .temporal: true
        }
    }

    public var kindLabel: String {
        switch self {
        case .openURL: "URL"
        case .webSearch: "Search"
        case .terminal: "Terminal"
        case .calculation(_, _, let kind, _):
            switch kind {
            case .arithmetic: "Calculator"
            case .measurement: "Units"
            case .currency: "Currency"
            }
        case .temporal(let calculation): calculation.kindLabel
        }
    }

    public var copyText: String? {
        switch self {
        case .openURL, .webSearch, .terminal: nil
        case .calculation(_, let value, let kind, let locale): Self.copyText(value: value, kind: kind, locale: locale)
        case .temporal(let calculation): calculation.copyText
        }
    }

    private static func title(value: Double, kind: CalculationKind, locale: Locale) -> String {
        switch kind {
        case .arithmetic: value.formatted(.number.precision(.fractionLength(0...6)).locale(locale))
        case .measurement(let result): result
        case .currency(let result, _): result
        }
    }

    private static func subtitle(input: String, kind: CalculationKind, locale: Locale) -> String {
        switch kind {
        case .arithmetic, .measurement: input
        case .currency(_, let updated): "\(input) · rate updated \(updated.formatted(Date.RelativeFormatStyle(presentation: .numeric, locale: locale)))"
        }
    }

    private static func copyText(value: Double, kind: CalculationKind, locale: Locale) -> String {
        switch kind {
        case .arithmetic, .measurement: value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)).locale(locale))
        case .currency: value.formatted(.number.grouping(.never).precision(.fractionLength(2)).locale(locale))
        }
    }

    public static func calculation(for query: String, rates: CurrencyRates? = nil, defaultCurrency: String? = nil, now: Date = Date(),
                                   timeZone: TimeZone = .current, locale: Locale = .current) -> QuickAction? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        switch TemporalCalc.recognize(trimmed, now: now, timeZone: timeZone, locale: locale) {
        case .value(let calculation): return .temporal(calculation)
        case .rejected: return nil
        case .notTemporal: break
        }
        if let value = Arithmetic.evaluate(trimmed) {
            return .calculation(input: trimmed, value: value, kind: .arithmetic, locale: locale)
        }
        if let conversion = UnitConversion.evaluate(trimmed, locale: locale) {
            return .calculation(input: conversion.input, value: conversion.value, kind: .measurement(result: conversion.result), locale: locale)
        }
        if let rates, let exchange = CurrencyConversion.evaluate(trimmed, rates: rates, defaultCurrency: defaultCurrency, locale: locale) {
            return .calculation(input: exchange.input, value: exchange.value, kind: .currency(result: exchange.result, updated: exchange.updated), locale: locale)
        }
        return nil
    }

    private static func displayHostPath(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        var text = host + url.path
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    public static func detectURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else { return nil }
            if let host = url.host, !host.isEmpty { return url }
            return scheme == "http" || scheme == "https" ? nil : url
        }
        let stopChars: Set<Character> = ["/", "?", ":"]
        let head = String(trimmed.prefix { !stopChars.contains($0) })
        guard head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        guard let firstDot = head.firstIndex(of: "."), let lastDot = head.lastIndex(of: ".") else { return nil }
        guard firstDot != head.startIndex, lastDot != head.index(before: head.endIndex) else { return nil }
        let lastLabel = head[head.index(after: lastDot)...]
        guard lastLabel.count >= 2, lastLabel.allSatisfy({ $0.isLetter }) else { return nil }
        return URL(string: "https://" + trimmed)
    }

    public static func fallbacks(for query: String, searchTemplate: String?) -> [QuickAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") {
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? [] : [.terminal(rest)]
        }
        var actions: [QuickAction] = []
        if let url = detectURL(trimmed) {
            actions.append(.openURL(url))
        }
        if let template = searchTemplate, let searchURL = URLTemplate.resolve(template: template, query: trimmed) {
            actions.append(.webSearch(query: trimmed, url: searchURL))
        }
        return actions
    }
}
