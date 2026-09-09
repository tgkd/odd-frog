import Foundation
import OddFrogCore
import OddFrogPluginAPI

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


extension LauncherItem {
    public static func app(_ item: AppItem) -> Self { .plugin(PluginResult(pluginID: "applications", item: FeatureProvider.application(item), generation: unhostedGeneration, catalog: true)) }
    public static func command(_ item: CommandItem) -> Self { .plugin(PluginResult(pluginID: "commands", item: FeatureProvider.command(item, shell: "/bin/zsh"), generation: unhostedGeneration, catalog: true)) }
    public static func script(_ item: ScriptItem) -> Self { .plugin(PluginResult(pluginID: "scripts", item: FeatureProvider.script(item), generation: unhostedGeneration, catalog: true)) }
    public static func window(_ item: WindowItem) -> Self {
        .plugin(PluginResult(pluginID: "windows", item: PluginItem(id: String(item.id.dropFirst(7)), title: item.action.title, subtitle: item.action.subtitle, kind: "Window", aliases: item.aliases, history: true), generation: unhostedGeneration, catalog: true))
    }
}
private let unhostedGeneration = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
