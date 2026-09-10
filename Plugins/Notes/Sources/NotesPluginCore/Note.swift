import Foundation

public struct Note: Sendable, Hashable {
    public let id: String
    public var text: String
    public var modified: Date
    public init(id: String, text: String, modified: Date) {
        self.id = id
        self.text = text
        self.modified = modified
    }
    public static func title(of text: String) -> String {
        guard let line = lines(of: text).first else {
            return "Untitled"
        }
        return String(line.prefix(80))
    }
    public static func snippet(of text: String) -> String? {
        let values = lines(of: text)
        guard values.count > 1 else {
            return nil
        }
        return String(values[1].prefix(80))
    }
    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
