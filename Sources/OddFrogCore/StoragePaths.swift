import Foundation
import CryptoKit
import OddFrogPluginAPI

public enum StoragePaths {
    public static var legacySupport: URL {
        if let path = ProcessInfo.processInfo.environment["ODD_FROG_SUPPORT_HOME"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return         FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("odd-frog", isDirectory: true)
    }
    public static var support: URL { legacySupport.appendingPathComponent("v2", isDirectory: true) }
    public static func stableID(_ name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

public enum V2Migration {
    /// Both destinations are staged and decoded before activation. The config rename is the commit point.
    public static func migrate(configRoot: URL = ConfigLoader.legacyDirectory, supportRoot: URL = StoragePaths.legacySupport,
                               packages: [PluginPackage] = []) throws {
        let fm = FileManager.default
        let destination = configRoot.appendingPathComponent("v2")
        let support = supportRoot.appendingPathComponent("v2")
        if fm.fileExists(atPath: destination.appendingPathComponent("migration-complete").path) { return }
        guard !fm.fileExists(atPath: destination.path) else {
            throw PluginError.message("Incomplete or manually created v2 configuration at \(destination.path). Move it aside and choose Retry Migration; original files are preserved.")
        }
        let stage = configRoot.appendingPathComponent(".v2-migration")
        let supportStage = supportRoot.appendingPathComponent(".v2-migration")
        try fm.createDirectory(at: configRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        // These paths are reserved staging directories; they are never activated.
        for url in [stage, supportStage] {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: stage); try? fm.removeItem(at: supportStage) }
        func read(_ name: String) throws -> String {
            let url = configRoot.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { return "" }
            return try String(contentsOf: url, encoding: .utf8)
        }
        var text = try read("config.toml")
        let original = try ConfigParser.parse(text)
        var settings = try Settings.parse(read("settings.toml"))
        text = try ConfigParser.serialized(original)
        _ = try ConfigParser.parse(text)
        func identity(_ id: String) -> String {
            if id.hasPrefix("plugin:") { return id }
            if id.hasPrefix("command:") {
                let name = String(id.dropFirst(8))
                let local = original.commands.first { $0.name == name || $0.stableID == name }?.stableID ?? StoragePaths.stableID(name)
                return "plugin:commands:\(local)"
            }
            if id.hasPrefix("script:") { return "plugin:scripts:" + id.dropFirst(7) }
            if id.hasPrefix("window:") { return "plugin:windows:" + id.dropFirst(7) }
            if id.hasPrefix("/") { return "plugin:applications:" + id }
            return id
        }
        settings.items = settings.items.map { ItemOverride(id: identity($0.id), enabled: $0.enabled, aliases: $0.aliases, hotkey: $0.hotkey) }
        let oldPlugins = settings.plugins
        settings.plugins = packages.map { package in
            let id = package.manifest.id
            let old = oldPlugins.first { $0.id == id }
            var values = old?.values ?? [:]
            var enabled = old?.enabled ?? (package.bundled && package.manifest.enabledByDefault)
            switch id {
            case "scripts": values["folders"] = .array(settings.scripts.folders.map(JSONValue.string)); values["watch"] = .bool(settings.scripts.watch)
            case "web": values["url"] = .string(settings.search.url)
            case "calculator": values["currency"] = .bool(settings.currency.enabled)
            case "windows": enabled = settings.window.enabled; values["cascade_step"] = .number(settings.window.cascadeStep)
            default: break
            }
            // Existing explicit user approvals are migrated only to their actual installed source.
            return PluginSetting(id: id, enabled: enabled, source: package.source, values: values.isEmpty ? nil : values)
        }
        settings.plugins += oldPlugins.filter { old in !packages.contains { $0.manifest.id == old.id } }.map {
            PluginSetting(id: $0.id, enabled: false, source: $0.source, values: $0.values)
        }
        for package in packages where package.manifest.apiVersion == 2 {
            _ = try package.manifest.validatedSettings(settings.plugins.first { $0.id == package.manifest.id }?.values ?? [:])
        }
        try Data(text.utf8).write(to: stage.appendingPathComponent("config.toml"))
        _ = try SettingsLoader.save(settings, to: stage.appendingPathComponent("settings.toml"))
        _ = try SettingsLoader.load(from: stage.appendingPathComponent("settings.toml"))
        let history = supportRoot.appendingPathComponent("frecency.json")
        if fm.fileExists(atPath: history.path) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let table = try decoder.decode(FrecencyTable.self, from: Data(contentsOf: history))
            guard table.entries.values.allSatisfy({ $0.weight.isFinite && $0.weight >= 0 }) else { throw PluginError.message("Invalid legacy history weight in \(history.path).") }
            let mapped = FrecencyTable(entries: Dictionary(table.entries.map { (identity($0.key), $0.value) }, uniquingKeysWith: { a, b in a.lastUsed > b.lastUsed ? a : b }))
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(mapped).write(to: supportStage.appendingPathComponent("frecency.json"))
        }
        let rates = supportRoot.appendingPathComponent("rates.json")
        if fm.fileExists(atPath: rates.path) {
            let data = try Data(contentsOf: rates)
            struct LegacyRates: Decodable { var base: String; var timestamp: Date; var fetched: Date?; var rates: [String: Double] }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(LegacyRates.self, from: data)
            guard !value.base.isEmpty, !value.rates.isEmpty, value.rates.values.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                throw PluginError.message("Invalid legacy currency cache: \(rates.path).")
            }
            let folder = supportStage.appendingPathComponent("plugins/calculator")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("rates.json"))
        }
        let plugins = configRoot.appendingPathComponent("plugins")
        if fm.fileExists(atPath: plugins.path) { try fm.copyItem(at: plugins, to: stage.appendingPathComponent("plugins")) }
        // User paths change during copying, so their approval is rebound to the migrated package directory.
        settings.plugins = settings.plugins.map { setting in
            var value = setting
            if let source = value.source, source.hasPrefix("user:" + plugins.path + "/") {
                value.source = source.replacingOccurrences(of: "user:" + plugins.path + "/", with: "user:" + destination.appendingPathComponent("plugins").path + "/")
            }
            return value
        }
        _ = try SettingsLoader.save(settings, to: stage.appendingPathComponent("settings.toml"))
        try Data("2\n".utf8).write(to: supportStage.appendingPathComponent("migration-owned"))
        if fm.fileExists(atPath: support.path) {
            guard fm.fileExists(atPath: support.appendingPathComponent("migration-owned").path) else { throw PluginError.message("Existing v2 application support was not created by migration: \(support.path). Move it aside to retry.") }
            try fm.removeItem(at: support)
        }
        try fm.moveItem(at: supportStage, to: support)
        try Data("2\n".utf8).write(to: stage.appendingPathComponent("migration-complete"))
        try fm.moveItem(at: stage, to: destination)
    }
}
