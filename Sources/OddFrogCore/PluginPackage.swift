import Foundation
import TOMLKit
import OddFrogPluginAPI

public struct PluginSettingDefinition: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case boolean, string, number, choice, folders }
    public var key: String
    public var title: String
    public var type: Kind
    public var defaultValue: JSONValue
    public var choices: [String]?
    public var minimum: Double?
    public var maximum: Double?
    enum CodingKeys: String, CodingKey { case key, title, type, choices, minimum, maximum; case defaultValue = "default" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key); title = try c.decode(String.self, forKey: .title)
        type = try c.decode(Kind.self, forKey: .type); defaultValue = try c.decode(JSONValue.self, forKey: .defaultValue)
        choices = try c.decodeIfPresent([String].self, forKey: .choices)
        minimum = try (try? c.decode(Int.self, forKey: .minimum)).map(Double.init) ?? (try c.decodeIfPresent(Double.self, forKey: .minimum))
        maximum = try (try? c.decode(Int.self, forKey: .maximum)).map(Double.init) ?? (try c.decodeIfPresent(Double.self, forKey: .maximum))
    }
    public func validate(_ value: JSONValue) throws {
        let valid: Bool
        switch type {
        case .boolean: valid = value.bool != nil
        case .string: valid = value.string != nil
        case .number:
            valid = value.number.map { $0.isFinite && $0 >= (minimum ?? -Double.greatestFiniteMagnitude) && $0 <= (maximum ?? Double.greatestFiniteMagnitude) } ?? false
        case .choice: valid = value.string.map { choices?.contains($0) == true } ?? false
        case .folders: valid = value.array.map { $0.allSatisfy { $0.string?.isEmpty == false } } ?? false
        }
        guard valid else { throw PluginError.message("Invalid setting '\(key)' (expected \(type.rawValue)).") }
    }
}
public struct PluginManifest: Decodable, Sendable, Equatable {
    public enum Mode: String, Decodable, Sendable { case declarative, oneShot = "one-shot", persistent }
    public enum Activation: String, Decodable, Sendable { case exclusive, live, fallback }
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let mode: Mode
    public let executable: String?
    public let activation: Activation?
    public let keyword: String?
    public let prefix: String?
    public let order: Int
    public let catalog: Bool
    public let background: Bool
    public let enabledByDefault: Bool
    public let capabilities: [String]
    public let settings: [PluginSettingDefinition]
    public let commands: [PluginItem]
    enum CodingKeys: String, CodingKey {
        case id, name, version, mode, executable, activation, keyword, prefix, order, catalog, background, capabilities, settings, commands
        case apiVersion = "api_version", enabledByDefault = "enabled_by_default"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version); apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .oneShot
        executable = try c.decodeIfPresent(String.self, forKey: .executable)
        activation = try c.decodeIfPresent(Activation.self, forKey: .activation)
        keyword = try c.decodeIfPresent(String.self, forKey: .keyword); prefix = try c.decodeIfPresent(String.self, forKey: .prefix)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        catalog = try c.decodeIfPresent(Bool.self, forKey: .catalog) ?? false
        background = try c.decodeIfPresent(Bool.self, forKey: .background) ?? false
        enabledByDefault = try c.decodeIfPresent(Bool.self, forKey: .enabledByDefault) ?? true
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        settings = try c.decodeIfPresent([PluginSettingDefinition].self, forKey: .settings) ?? []
        commands = try c.decodeIfPresent([PluginItem].self, forKey: .commands) ?? []
    }
    public static func parse(_ text: String) throws -> Self {
        let value = try TOMLDecoder().decode(Self.self, from: text)
        guard value.id.range(of: "^[a-z0-9][a-z0-9.-]{0,63}$", options: .regularExpression) != nil,
              !value.name.isEmpty, !value.version.isEmpty else { throw PluginError.message("Invalid plugin metadata.") }
        if value.apiVersion != PluginProtocol.version { return value } // Keep incompatible packages visible.
        if value.mode != .declarative {
            if let executable = value.executable {
                guard !executable.isEmpty, !executable.hasPrefix("/"),
                      !executable.split(separator: "/").contains("..") else { throw PluginError.message("Invalid executable path.") }
            }
        } else if value.activation != nil || value.catalog || value.background {
            throw PluginError.message("Declarative plugins can only declare static commands.")
        }
        if value.activation == .exclusive {
            guard (value.keyword != nil) != (value.prefix != nil),
                  value.keyword.map({ $0.range(of: "^[a-z][a-z0-9_-]*$", options: .regularExpression) != nil }) ?? true,
                  value.prefix.map({ !$0.isEmpty && !$0.contains(where: \.isWhitespace) }) ?? true else {
                throw PluginError.message("Exclusive activation requires one valid keyword or prefix.")
            }
        } else if value.keyword != nil || value.prefix != nil { throw PluginError.message("Triggers require exclusive activation.") }
        guard Set(value.settings.map(\.key)).count == value.settings.count else { throw PluginError.message("Duplicate settings keys.") }
        for setting in value.settings {
            guard !setting.key.isEmpty, !setting.title.isEmpty else { throw PluginError.message("Empty setting key or title.") }
            try setting.validate(setting.defaultValue)
        }
        return value
    }
    public func validatedSettings(_ values: [String: JSONValue]) throws -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for definition in settings {
            let value = values[definition.key] ?? definition.defaultValue
            try definition.validate(value); result[definition.key] = value
        }
        guard values.keys.allSatisfy({ result[$0] != nil }) else { throw PluginError.message("Unknown plugin setting. Reload the package or remove the obsolete key.") }
        return result
    }
}
public struct PluginSetting: Codable, Sendable, Equatable {
    public var id: String
    public var enabled: Bool
    public var source: String?
    public var values: [String: JSONValue]?
    public init(id: String, enabled: Bool, source: String? = nil, values: [String: JSONValue]? = nil) {
        self.id = id; self.enabled = enabled; self.source = source; self.values = values
    }
}
public struct PluginPackage: Sendable, Equatable {
    public let manifest: PluginManifest
    public let directory: URL
    public let bundled: Bool
    public var executable: URL { directory.appendingPathComponent(manifest.executable ?? "") }
    public var source: String { bundled ? "bundled" : "user:" + directory.resolvingSymlinksInPath().path }
    public init(manifest: PluginManifest, directory: URL, bundled: Bool) {
        self.manifest = manifest; self.directory = directory; self.bundled = bundled
    }
    public func setting(in settings: [PluginSetting]) -> PluginSetting? {
        settings.first { $0.id == manifest.id && ($0.source == source || (bundled && $0.source?.hasPrefix("bundled:") == true)) }
    }
    public func isEnabled(settings: [PluginSetting]) -> Bool {
        if let setting = setting(in: settings) { return setting.enabled }
        return bundled && manifest.enabledByDefault
    }
    public func query(from fullQuery: String) -> String? {
        let text = fullQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let activation = manifest.activation, !text.isEmpty else { return nil }
        if activation != .exclusive { return text }
        if let prefix = manifest.prefix { return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : nil }
        let parts = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first?.lowercased() == manifest.keyword else { return nil }
        return parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}
public enum PluginError: Error, CustomStringConvertible {
    case message(String)
    public var description: String { switch self { case .message(let text): text } }
}
public struct PluginDiscovery: Sendable {
    public var packages: [PluginPackage]
    public var errors: [String]
    public init(packages: [PluginPackage], errors: [String] = []) { self.packages = packages; self.errors = errors }
    public static func scan(bundled: URL?, user: URL) -> Self {
        var errors: [String] = []
        func read(_ root: URL?, bundled: Bool) -> [String: PluginPackage] {
            guard let root, FileManager.default.fileExists(atPath: root.path) else { return [:] }
            var packages: [String: PluginPackage] = [:]
            var duplicates = Set<String>()
            do {
                for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).sorted(by: { $0.path < $1.path }) {
                    let file = folder.appendingPathComponent("plugin.toml")
                    guard FileManager.default.fileExists(atPath: file.path) else { continue }
                    do {
                        let manifest = try PluginManifest.parse(String(contentsOf: file, encoding: .utf8))
                        if packages[manifest.id] != nil { duplicates.insert(manifest.id) }
                        packages[manifest.id] = PluginPackage(manifest: manifest, directory: folder, bundled: bundled)
                    } catch { errors.append("\(folder.path): \(error)") }
                }
            } catch { errors.append("\(root.path): \(error)") }
            for id in duplicates { packages.removeValue(forKey: id); errors.append("Ambiguous plugin ID '\(id)' in \(root.path).") }
            return packages
        }
        let merged = read(bundled, bundled: true).merging(read(user, bundled: false)) { _, user in user }
        return Self(packages: merged.values.sorted {
            if $0.manifest.order != $1.manifest.order { return $0.manifest.order < $1.manifest.order }
            return $0.manifest.id < $1.manifest.id
        }, errors: errors)
    }
}
