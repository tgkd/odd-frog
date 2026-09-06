import Foundation

public enum QuickAction: Sendable, Hashable {
    case openURL(URL)
    case webSearch(query: String, url: URL)
    case terminal(String)

    public var id: String {
        switch self {
        case .openURL(let url): "quick:url:\(url.absoluteString)"
        case .webSearch(let query, _): "quick:search:\(query)"
        case .terminal(let text): "quick:terminal:\(text)"
        }
    }

    public var title: String {
        switch self {
        case .openURL(let url): "Open \(Self.displayHostPath(url))"
        case .webSearch(let query, _): "Search for “\(query)”"
        case .terminal: "Run in Terminal"
        }
    }

    public var subtitle: String? {
        switch self {
        case .openURL: nil
        case .webSearch(_, let url): url.host
        case .terminal(let text): text
        }
    }

    public var kindLabel: String {
        switch self {
        case .openURL: "URL"
        case .webSearch: "Search"
        case .terminal: "Terminal"
        }
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
