import Foundation
import TOMLKit

public struct ItemOverride: Codable, Sendable, Equatable {
    public var id: String
    public var enabled: Bool
    public var aliases: [String]
    public var hotkey: String?

    public init(id: String, enabled: Bool = true, aliases: [String] = [], hotkey: String? = nil) {
        self.id = id
        self.enabled = enabled
        self.aliases = aliases
        self.hotkey = hotkey
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case aliases
        case hotkey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey)
    }

    public var isDefault: Bool { enabled && aliases.isEmpty && hotkey == nil }
}

public struct Settings: Codable, Sendable, Equatable {
    public struct Scripts: Codable, Sendable, Equatable {
        public var folders: [String]
        public var watch: Bool

        public init(folders: [String] = [], watch: Bool = true) {
            self.folders = folders
            self.watch = watch
        }

        enum CodingKeys: String, CodingKey {
            case folders
            case watch
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folders = try container.decodeIfPresent([String].self, forKey: .folders) ?? []
            watch = try container.decodeIfPresent(Bool.self, forKey: .watch) ?? true
        }
    }

    public struct Search: Codable, Sendable, Equatable {
        public static let defaultURL = "https://duckduckgo.com/?q={query}"

        public var url: String

        public init(url: String = Search.defaultURL) {
            self.url = url
        }

        enum CodingKeys: String, CodingKey {
            case url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decoded = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            url = decoded.isEmpty ? Search.defaultURL : decoded
        }
    }

    public struct Currency: Codable, Sendable, Equatable {
        public var enabled: Bool

        public init(enabled: Bool = true) {
            self.enabled = enabled
        }

        enum CodingKeys: String, CodingKey {
            case enabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    public struct Window: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var cascadeStep: Double

        public init(enabled: Bool = false, cascadeStep: Double = 32) {
            self.enabled = enabled
            self.cascadeStep = (16...120).contains(cascadeStep) ? cascadeStep : 32
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case cascadeStep = "cascade_step"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            let step: Double
            if let integer = try? container.decode(Int.self, forKey: .cascadeStep) {
                step = Double(integer)
            } else {
                step = try container.decodeIfPresent(Double.self, forKey: .cascadeStep) ?? 32
            }
            self.init(enabled: enabled, cascadeStep: step)
        }
    }

    public struct Appearance: Codable, Sendable, Equatable {
        public enum Theme: String, Codable, Sendable, CaseIterable {
            case system
            case light
            case dark
        }

        public static let defaultSize: Double = 13
        public static let sizeRange: ClosedRange<Double> = 10...24

        public var theme: Theme
        public var fontFamily: String?
        public var fontSize: Double

        public init(theme: Theme = .system, fontFamily: String? = nil, fontSize: Double = Appearance.defaultSize) {
            self.theme = theme
            let trimmed = fontFamily?.trimmingCharacters(in: .whitespaces) ?? ""
            self.fontFamily = trimmed.isEmpty ? nil : trimmed
            self.fontSize = min(max(fontSize, Appearance.sizeRange.lowerBound), Appearance.sizeRange.upperBound)
        }

        enum CodingKeys: String, CodingKey {
            case theme
            case fontFamily = "font_family"
            case fontSize = "font_size"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let theme: Theme
            if let raw = try? container.decodeIfPresent(String.self, forKey: .theme) {
                theme = Theme(rawValue: raw) ?? .system
            } else {
                theme = .system
            }
            let family = try container.decodeIfPresent(String.self, forKey: .fontFamily)
            let size: Double
            if let integer = try? container.decode(Int.self, forKey: .fontSize) {
                size = Double(integer)
            } else {
                size = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Appearance.defaultSize
            }
            self.init(theme: theme, fontFamily: family, fontSize: size)
        }
    }

    public var scripts: Scripts
    public var items: [ItemOverride]
    public var search: Search
    public var currency: Currency
    public var window: Window
    public var appearance: Appearance
    public var plugins: [PluginSetting]

    public init(scripts: Scripts = Scripts(), items: [ItemOverride] = [], search: Search = Search(), currency: Currency = Currency(), window: Window = Window(), plugins: [PluginSetting] = [], appearance: Appearance = Appearance()) {
        self.scripts = scripts
        self.items = items
        self.search = search
        self.currency = currency
        self.window = window
        self.plugins = plugins
        self.appearance = appearance
    }

    enum CodingKeys: String, CodingKey {
        case scripts
        case items
        case search
        case currency
        case window
        case appearance
        case plugins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scripts = try container.decodeIfPresent(Scripts.self, forKey: .scripts) ?? Scripts()
        items = try container.decodeIfPresent([ItemOverride].self, forKey: .items) ?? []
        search = try container.decodeIfPresent(Search.self, forKey: .search) ?? Search()
        currency = try container.decodeIfPresent(Currency.self, forKey: .currency) ?? Currency()
        window = try container.decodeIfPresent(Window.self, forKey: .window) ?? Window()
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? Appearance()
        plugins = try container.decodeIfPresent([PluginSetting].self, forKey: .plugins) ?? []
    }

    public static let empty = Settings()

    public var scriptFolders: [URL] {
        scripts.folders.map { URL(fileURLWithPath: ConfigParser.expandTilde($0), isDirectory: true) }
    }

    public func override(for id: String) -> ItemOverride? {
        items.first { $0.id == id }
    }

    public mutating func setOverride(_ override: ItemOverride) {
        items.removeAll { $0.id == override.id }
        if !override.isDefault { items.append(override) }
        items.sort { $0.id < $1.id }
    }

    public func apply(to items: [LauncherItem]) -> [LauncherItem] {
        guard !self.items.isEmpty else { return items }
        let overrides = Dictionary(self.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return items.compactMap { item in
            guard let override = overrides[item.id] else { return item }
            guard override.enabled else { return nil }
            return item.withAliases(override.aliases)
        }
    }

    public static func parse(_ text: String) throws -> Settings {
        do {
            var settings = try TOMLDecoder().decode(Settings.self, from: text)
            settings.items = settings.items.map { override in
                var o = override
                o.aliases = o.aliases.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                let hotkey = o.hotkey?.trimmingCharacters(in: .whitespaces) ?? ""
                o.hotkey = hotkey.isEmpty ? nil : hotkey
                return o
            }
            return settings
        } catch let error as TOMLParseError {
            throw ConfigError.toml("\(error.source.begin.line):\(error.source.begin.column) \(error.description)")
        } catch {
            throw ConfigError.toml(String(describing: error))
        }
    }

    public func serialized() throws -> String {
        try TOMLEncoder().encode(self)
    }
}

public enum SettingsLoader {
    public static var defaultPath: URL {
        ConfigLoader.defaultDirectory.appendingPathComponent("settings.toml")
    }

    public static func load(from url: URL) throws -> (settings: Settings, contents: Data) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw ConfigError.toml("file is not UTF-8") }
        return (try Settings.parse(text), data)
    }

    @discardableResult
    public static func save(_ settings: Settings, to url: URL) throws -> Data {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(try settings.serialized().utf8)
        try data.write(to: url, options: .atomic)
        return data
    }
}
