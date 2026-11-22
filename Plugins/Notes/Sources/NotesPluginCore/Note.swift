import Foundation
import OddFrogHostServicesAPI

public struct Note: Sendable, Hashable {
    public let id: String
    public var text: String
    public var modified: Date
    public init(id: String, text: String, modified: Date) {
        self.id = id
        self.text = text
        self.modified = modified
    }
    public init(_ record: NoteRecord) {
        self.init(id: record.id, text: record.text, modified: record.modified)
    }
    public static func title(of text: String) -> String {
        NoteText.title(of: text)
    }
    public static func snippet(of text: String) -> String? {
        NoteText.snippet(of: text)
    }
}
