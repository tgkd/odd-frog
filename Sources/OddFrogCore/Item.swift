import Foundation

public struct AppItem: Sendable, Hashable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    public var aliases: [String]

    public init(url: URL, name: String, bundleID: String?, aliases: [String] = []) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.aliases = aliases
    }

    public var id: String { url.path }
}

public enum CommandAction: Sendable, Hashable {
    case shell(String)
    case path(URL)
    case url(URL)
}

public struct CommandItem: Sendable, Hashable {
    public let name: String
    public var aliases: [String]
    public let action: CommandAction
    public let cwd: URL?
    public let terminal: Bool

    public init(name: String, aliases: [String], action: CommandAction, cwd: URL?, terminal: Bool) {
        self.name = name
        self.aliases = aliases
        self.action = action
        self.cwd = cwd
        self.terminal = terminal
    }

    public var id: String { "command:\(name)" }
}

public enum ScriptMode: String, Sendable, Hashable {
    case silent
    case fullOutput
    case inline
}

public struct ScriptArgument: Sendable, Hashable {
    public let placeholder: String
    public let optional: Bool

    public init(placeholder: String, optional: Bool) {
        self.placeholder = placeholder
        self.optional = optional
    }
}

public struct ScriptItem: Sendable, Hashable {
    public let url: URL
    public let title: String
    public let mode: ScriptMode
    public let icon: String?
    public let package: String?
    public let argument: ScriptArgument?
    public var aliases: [String]

    public init(url: URL, title: String, mode: ScriptMode, icon: String?, package: String?, argument: ScriptArgument?, aliases: [String] = []) {
        self.url = url
        self.title = title
        self.mode = mode
        self.icon = icon
        self.package = package
        self.argument = argument
        self.aliases = aliases
    }

    public var id: String { "script:\(url.path)" }
}

public struct WindowItem: Sendable, Hashable {
    public let action: WindowAction
    public var aliases: [String]

    public init(action: WindowAction, aliases: [String] = []) {
        self.action = action
        self.aliases = aliases
    }

    public var id: String { action.id }
}

public enum LauncherItem: Sendable, Hashable {
    case app(AppItem)
    case command(CommandItem)
    case script(ScriptItem)
    case quick(QuickAction)
    case window(WindowItem)
    case plugin(PluginResult)

    public var id: String {
        switch self {
        case .app(let app): app.id
        case .command(let command): command.id
        case .script(let script): script.id
        case .quick(let quick): quick.id
        case .window(let item): item.action.id
        case .plugin(let result): result.id
        }
    }

    public var title: String {
        switch self {
        case .app(let app): app.name
        case .command(let command): command.name
        case .script(let script): script.title
        case .quick(let quick): quick.title
        case .window(let item): item.action.title
        case .plugin(let result): result.item.title
        }
    }

    public var subtitle: String? {
        switch self {
        case .app:
            nil
        case .command(let command):
            switch command.action {
            case .shell: nil
            case .path(let url): Self.abbreviate(url.path)
            case .url(let url): Self.webAddress(url)
            }
        case .script(let script):
            script.package.flatMap { $0.caseInsensitiveCompare(script.title) == .orderedSame ? nil : $0 }
        case .quick(let quick):
            quick.subtitle
        case .window(let item):
            item.action.subtitle
        case .plugin(let result): result.item.subtitle
        }
    }

    private static func webAddress(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        var text = host + url.path
        while text.hasSuffix("/") { text.removeLast() }
        return text.replacingOccurrences(of: URLTemplate.encoded, with: URLTemplate.placeholder)
    }

    public static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    public static func subtitles(for items: [LauncherItem]) -> [String: String] {
        var byTitle: [String: [LauncherItem]] = [:]
        for item in items { byTitle[item.title.lowercased(), default: []].append(item) }
        var out: [String: String] = [:]
        for item in items {
            if let subtitle = item.subtitle {
                out[item.id] = subtitle
            } else if case .app(let app) = item, (byTitle[item.title.lowercased()]?.count ?? 0) > 1 {
                out[item.id] = abbreviate(app.url.deletingLastPathComponent().path)
            }
        }
        return out
    }

    public var aliases: [String] {
        switch self {
        case .app(let app): app.aliases
        case .command(let command): command.aliases
        case .script(let script): script.aliases
        case .quick, .plugin: []
        case .window(let item): item.aliases
        }
    }

    public var acceptsArgument: Bool {
        switch self {
        case .script(let script):
            return script.argument != nil
        case .command(let command):
            if case .url(let url) = command.action { return URLTemplate.accepts(url) }
            return false
        case .app:
            return false
        case .quick, .window, .plugin:
            return false
        }
    }

    public var kindLabel: String? {
        switch self {
        case .app: nil
        case .command(let command):
            switch command.action {
            case .shell: command.terminal ? "Terminal" : "Shell"
            case .path: "Folder"
            case .url: "URL"
            }
        case .script:
            "Script"
        case .quick(let quick):
            quick.kindLabel
        case .window(let item):
            item.action.kindLabel
        case .plugin(let result): result.item.kind
        }
    }

    public func withAliases(_ extra: [String]) -> LauncherItem {
        guard !extra.isEmpty else { return self }
        switch self {
        case .app(var app):
            app.aliases = merged(app.aliases, extra)
            return .app(app)
        case .command(var command):
            command.aliases = merged(command.aliases, extra)
            return .command(command)
        case .script(var script):
            script.aliases = merged(script.aliases, extra)
            return .script(script)
        case .window(var item):
            item.aliases = merged(item.aliases, extra)
            return .window(item)
        case .quick, .plugin:
            return self
        }
    }

    private func merged(_ base: [String], _ extra: [String]) -> [String] {
        var seen = Set(base)
        return base + extra.filter { seen.insert($0).inserted }
    }
}
