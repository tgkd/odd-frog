import Foundation

public struct NotesQuery: Codable, Sendable, Equatable {
    public var query: String
    public var limit: Int

    public init(query: String = "", limit: Int = 20) {
        self.query = query
        self.limit = limit
    }

    public func isValid() -> Bool {
        (1...200).contains(limit) && query.count <= 500
    }
}

public struct NoteRecord: Codable, Sendable, Equatable {
    public var id: String
    public var text: String
    public var modified: Date

    public init(id: String, text: String, modified: Date) {
        self.id = id
        self.text = text
        self.modified = modified
    }
}

public struct NotesSnapshot: Codable, Sendable, Equatable {
    public var notes: [NoteRecord]
    public var truncated: Bool

    public init(notes: [NoteRecord] = [], truncated: Bool = false) {
        self.notes = notes
        self.truncated = truncated
    }
}

public struct NoteAppend: Codable, Sendable, Equatable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public enum NoteText {
    public static let maximumLength = 100_000

    public static func isValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text.count <= maximumLength
    }
}
