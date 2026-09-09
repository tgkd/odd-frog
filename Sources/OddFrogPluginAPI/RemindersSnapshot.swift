import Foundation

public struct RemindersScope: Codable, Sendable, Equatable {
    public var limit: Int

    public init(limit: Int) {
        self.limit = limit
    }

    public func isValid() -> Bool {
        (1...2000).contains(limit)
    }
}

public struct ReminderItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var due: Date?
    public var allDay: Bool
    public var listName: String
    public var priority: Int
    public var url: String?

    public init(id: String, title: String, due: Date? = nil, allDay: Bool = false,
                listName: String = "", priority: Int = 0, url: String? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.allDay = allDay
        self.listName = listName
        self.priority = priority
        self.url = url
    }
}

public struct RemindersSnapshot: Codable, Sendable, Equatable {
    public enum Access: String, Codable, Sendable { case notDetermined, fullAccess, denied, restricted, writeOnly }
    public var access: Access
    public var reminders: [ReminderItem]
    public var truncated: Bool
    public var defaultListName: String?

    public init(access: Access, reminders: [ReminderItem] = [], truncated: Bool = false,
                defaultListName: String? = nil) {
        self.access = access
        self.reminders = reminders
        self.truncated = truncated
        self.defaultListName = defaultListName
    }
}
