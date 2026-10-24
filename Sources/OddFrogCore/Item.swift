import Foundation
import OddFrogPluginAPI

public enum CommandAction: Sendable, Hashable {
    case shell(String)
    case path(URL)
    case url(URL)
}

public struct CommandItem: Sendable, Hashable, Identifiable {
    public var stableID: String
    public let name: String
    public var aliases: [String]
    public let action: CommandAction
    public let cwd: URL?
    public let terminal: Bool
    /// Global shortcut from config; an item override in settings replaces it.
    public var hotkey: Hotkey?

    public init(name: String, aliases: [String], action: CommandAction, cwd: URL?, terminal: Bool, stableID: String? = nil, hotkey: Hotkey? = nil) {
        self.stableID = stableID ?? StoragePaths.stableID(name)
        self.name = name
        self.aliases = aliases
        self.action = action
        self.cwd = cwd
        self.terminal = terminal
        self.hotkey = hotkey
    }

    public var id: String { "command:\(stableID)" }
    public static func itemID(forStableID stableID: String) -> String { "plugin:commands:" + stableID }
    public var itemID: String { Self.itemID(forStableID: stableID) }
}

public enum LauncherItem: Sendable, Hashable {
    case plugin(PluginResult)
    public var result: PluginResult { switch self { case .plugin(let value): value } }
    public var id: String { result.id }
    public var title: String { result.item.title }
    public var subtitle: String? { result.item.subtitle }
    public var aliases: [String] { result.item.aliases ?? [] }
    public var acceptsArgument: Bool { result.item.argument != nil }
    public var kindLabel: String? { result.item.kind }
    public func withAliases(_ extra: [String]) -> Self {
        var value = result
        var seen = Set(aliases)
        value.item.aliases = aliases + extra.filter { seen.insert($0).inserted }
        return .plugin(value)
    }
    public static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
    public static func subtitles(for items: [LauncherItem]) -> [String: String] {
        let groups = Dictionary(grouping: items, by: { $0.title.lowercased() })
        var out: [String: String] = [:]
        for item in items {
            if let subtitle = item.subtitle { out[item.id] = subtitle }
            else if (groups[item.title.lowercased()]?.count ?? 0) > 1,
                    let path = item.result.item.icon, path.hasPrefix("/") {
                out[item.id] = abbreviate(URL(fileURLWithPath: path).deletingLastPathComponent().path)
            }
        }
        return out
    }
}
