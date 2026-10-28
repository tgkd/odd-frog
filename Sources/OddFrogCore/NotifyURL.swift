import Foundation

public struct NotifyURL: Equatable, Sendable {
    public static let scheme = "odd-frog"
    public static let maxLength = 1000

    public var title: String?
    public var body: String

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == "notify",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            let trimmed = items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxLength))
        }
        guard let body = value("body") else { return nil }
        self.title = value("title")
        self.body = body
    }
}
