import Foundation

public enum PluginTrigger: Sendable, Equatable {
    case keyword(String)
    case prefix(String)

    public var text: String {
        switch self {
        case .keyword(let value):
            return value
        case .prefix(let value):
            return value
        }
    }

    public var label: String {
        switch self {
        case .keyword:
            return "Keyword"
        case .prefix:
            return "Prefix"
        }
    }

    public func replacing(_ text: String) throws -> PluginTrigger {
        switch self {
        case .keyword:
            guard text.range(of: "^[a-z][a-z0-9_-]*$", options: .regularExpression) != nil else {
                throw PluginError.message("Invalid keyword '\(text)'. Use a lowercase letter followed by letters, digits, - or _.")
            }
            return .keyword(text)
        case .prefix:
            guard !text.isEmpty, !text.contains(where: \.isWhitespace) else {
                throw PluginError.message("Invalid prefix '\(text)'. Use one or more characters without spaces.")
            }
            return .prefix(text)
        }
    }

    public func conflicts(with other: PluginTrigger) -> Bool {
        switch (self, other) {
        case (.keyword(let x), .keyword(let y)):
            return x == y
        case (.prefix(let x), .prefix(let y)):
            return x.hasPrefix(y) || y.hasPrefix(x)
        case (.keyword(let x), .prefix(let y)):
            return x.hasPrefix(y)
        case (.prefix(let x), .keyword(let y)):
            return y.hasPrefix(x)
        }
    }
}
