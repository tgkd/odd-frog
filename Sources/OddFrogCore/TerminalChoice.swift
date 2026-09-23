import Foundation
import OddFrogPluginAPI

public enum TerminalKind: String, Sendable, CaseIterable {
    case terminal = "Terminal"
    case agterm
    case iterm = "iTerm2"
}

public enum TerminalChoice: Sendable, Equatable {
    case preset(TerminalKind)
    case custom(String)

    public static let pluginID = "terminal"
    public static let customTitle = "Custom"

    public init(values: [String: JSONValue]?) {
        if values?["app"]?.string == Self.customTitle {
            self = .custom(values?["custom_command"]?.string ?? "")
        } else {
            self = .preset(TerminalKind(rawValue: values?["app"]?.string ?? "") ?? .terminal)
        }
    }
}