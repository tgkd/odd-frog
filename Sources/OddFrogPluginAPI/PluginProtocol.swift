import Foundation

public enum PluginProtocol {
    public static let version = 1
    public static let maxBytes = 4 * 1024 * 1024
    public static let calendarService = "calendar.events"
    public static let remindersService = "reminders.items"
    public static let services: Set<String> = [calendarService, remindersService]

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

public struct PluginRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case prepare, query }
    public var apiVersion = PluginProtocol.version
    public var id: String
    public var operation: Operation
    public var query: String
    public var fullQuery: String
    public var now: Date
    public var timeZoneIdentifier: String
    public var maxResults: Int
    public var calendar: CalendarSnapshot?
    public var reminders: RemindersSnapshot?

    public init(id: String = UUID().uuidString, operation: Operation = .prepare, query: String,
                fullQuery: String, now: Date = Date(), timeZoneIdentifier: String = TimeZone.current.identifier,
                maxResults: Int = 8, calendar: CalendarSnapshot? = nil, reminders: RemindersSnapshot? = nil) {
        self.id = id
        self.operation = operation
        self.query = query
        self.fullQuery = fullQuery
        self.now = now
        self.timeZoneIdentifier = timeZoneIdentifier
        self.maxResults = maxResults
        self.calendar = calendar
        self.reminders = reminders
    }
}

public struct PluginResponse: Codable, Sendable {
    public var apiVersion = PluginProtocol.version
    public var id: String
    public var calendarRequest: CalendarRange?
    public var remindersRequest: RemindersScope?
    public var items: [PluginItem]

    public init(id: String, calendarRequest: CalendarRange? = nil,
                remindersRequest: RemindersScope? = nil, items: [PluginItem] = []) {
        self.id = id
        self.calendarRequest = calendarRequest
        self.remindersRequest = remindersRequest
        self.items = items
    }
}
