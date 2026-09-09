import Foundation

public struct PluginAction: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case openURL, openApplication, copy, requestCalendarAccess, requestRemindersAccess
        case completeReminder, createReminder
    }
    public var kind: Kind
    public var value: String

    public init(_ kind: Kind, _ value: String = "") {
        self.kind = kind
        self.value = value
    }
}

public struct PluginItem: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var kind: String?
    public var symbol: String?
    public var completion: String?
    public var primary: PluginAction?
    public var secondary: PluginAction?

    public init(id: String, title: String, subtitle: String? = nil, kind: String? = nil,
                symbol: String? = nil, completion: String? = nil,
                primary: PluginAction? = nil, secondary: PluginAction? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.symbol = symbol
        self.completion = completion
        self.primary = primary
        self.secondary = secondary
    }
}
