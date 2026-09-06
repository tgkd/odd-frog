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

public enum LauncherItem: Sendable, Hashable {
    case app(AppItem)
    case command(CommandItem)
    case script(ScriptItem)

    public var id: String {
        switch self {
        case .app(let app): app.id
        case .command(let command): command.id
        case .script(let script): script.id
        }
    }

    public var title: String {
        switch self {
        case .app(let app): app.name
        case .command(let command): command.name
        case .script(let script): script.title
        }
    }

    public var subtitle: String? {
        switch self {
        case .app:
            nil
        case .command(let command):
            switch command.action {
            case .shell(let text): "$ \(text)"
            case .path(let url): Self.abbreviate(url.path)
            case .url(let url): url.absoluteString
            }
        case .script(let script):
            script.package.flatMap { $0.caseInsensitiveCompare(script.title) == .orderedSame ? nil : $0 }
        }
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
                out[item.id] = abbreviate(app.url.deletingLastPathComponent().path) + "/" + app.url.lastPathComponent
            }
        }
        return out
    }

    public var aliases: [String] {
        switch self {
        case .app(let app): app.aliases
        case .command(let command): command.aliases
        case .script(let script): script.aliases
        }
    }

    public var acceptsArgument: Bool {
        if case .script(let script) = self { return script.argument != nil }
        return false
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
        }
    }

    private func merged(_ base: [String], _ extra: [String]) -> [String] {
        var seen = Set(base)
        return base + extra.filter { seen.insert($0).inserted }
    }
}
