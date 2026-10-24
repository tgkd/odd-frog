import Foundation

public struct PluginAction: Codable, Sendable, Hashable {
    /// `paste` puts `value` on the clipboard and presses ⌘V in the app that was active before the
    /// launcher opened; `payload.png` names a PNG file to paste instead of text.
    public enum Kind: String, Codable, Sendable {
        case copy, paste, openURL, openPath, openApplication, reveal, execute, terminal, service, callback
    }
    public var kind: Kind
    public var value: String
    public var payload: JSONValue?
    public var argv: [String]?
    public var cwd: String?
    public var output: String?
    public init(_ kind: Kind, _ value: String = "", payload: JSONValue? = nil,
                argv: [String]? = nil, cwd: String? = nil, output: String? = nil) {
        self.kind = kind; self.value = value; self.payload = payload
        self.argv = argv; self.cwd = cwd; self.output = output
    }
}
public struct PluginArgument: Codable, Sendable, Hashable {
    public var placeholder: String
    public var optional: Bool
    public init(placeholder: String = "Argument", optional: Bool = false) {
        self.placeholder = placeholder; self.optional = optional
    }
}
public struct PluginItem: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var kind: String?
    public var symbol: String?
    public var icon: String?
    public var aliases: [String]?
    public var argument: PluginArgument?
    public var completion: String?
    public var primary: PluginAction?
    public var secondary: PluginAction?
    public var history: Bool?
    public init(id: String, title: String, subtitle: String? = nil, kind: String? = nil,
                symbol: String? = nil, icon: String? = nil, aliases: [String]? = nil,
                argument: PluginArgument? = nil, completion: String? = nil,
                primary: PluginAction? = nil, secondary: PluginAction? = nil, history: Bool? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind
        self.symbol = symbol; self.icon = icon; self.aliases = aliases; self.argument = argument
        self.completion = completion; self.primary = primary; self.secondary = secondary; self.history = history
    }
}
