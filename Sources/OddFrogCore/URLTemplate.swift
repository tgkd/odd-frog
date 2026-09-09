import Foundation

public enum URLTemplate {
    public static let placeholder = "{query}"
    public static let encoded = "%7Bquery%7D"

    public static func accepts(_ url: URL) -> Bool {
        url.absoluteString.contains(encoded)
    }

    public static func display(_ url: URL) -> String {
        url.absoluteString.replacingOccurrences(of: encoded, with: placeholder)
    }

    public static func encode(_ query: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
    }

    public static func resolve(_ url: URL, query: String) -> URL {
        let resolved = url.absoluteString.replacingOccurrences(of: encoded, with: encode(query))
        return URL(string: resolved) ?? url
    }

    public static func resolve(template: String, query: String) -> URL? {
        let resolved = template.replacingOccurrences(of: placeholder, with: encode(query))
        guard let url = URL(string: resolved), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }
}
