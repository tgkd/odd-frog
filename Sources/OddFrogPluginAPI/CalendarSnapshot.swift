import Foundation

public struct CalendarRange: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Host service boundary: at most 32 days, near the query's current time.
    public func isValid(relativeTo now: Date) -> Bool {
        let duration = end.timeIntervalSince(start)
        return duration.isFinite && duration > 0 && duration <= 32 * 86400
            && start >= now.addingTimeInterval(-2 * 86400)
            && end <= now.addingTimeInterval(32 * 86400)
    }
}

public struct CalendarEvent: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var calendarName: String
    public var location: String
    public var url: String?

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool = false,
                calendarName: String = "", location: String = "", url: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.calendarName = calendarName
        self.location = location
        self.url = url
    }
}

public struct CalendarSnapshot: Codable, Sendable, Equatable {
    public enum Access: String, Codable, Sendable { case notDetermined, fullAccess, denied, restricted, writeOnly }
    public var access: Access
    public var events: [CalendarEvent]

    public init(access: Access, events: [CalendarEvent] = []) {
        self.access = access
        self.events = events
    }
}
