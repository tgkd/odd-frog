import Foundation
import OddFrogPluginAPI

public struct Conversation: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var created: Date
    public var modified: Date
    public var messages: [PluginMessage]
    public init(id: String, title: String, created: Date, modified: Date, messages: [PluginMessage]) {
        self.id = id
        self.title = title
        self.created = created
        self.modified = modified
        self.messages = messages
    }
    public static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let collapsed = (line.map(String.init) ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else {
            return "New chat"
        }
        return String(collapsed.prefix(60))
    }
}
