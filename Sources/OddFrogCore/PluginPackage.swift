import Foundation
import TOMLKit
import OddFrogPluginAPI

public struct PluginManifest: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let executable: String
    public let keyword: String
    public let services: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, version, executable, keyword, services
        case apiVersion = "api_version"
    }

    public static func parse(_ text: String) throws -> PluginManifest {
        let value = try TOMLDecoder().decode(Self.self, from: text)
        let validID = value.id.range(of: "^[a-z0-9][a-z0-9.-]{0,63}$", options: .regularExpression) != nil
        let validKeyword = value.keyword.range(of: "^[a-z][a-z0-9_-]*$", options: .regularExpression) != nil
        guard validID, validKeyword, !value.name.isEmpty, !value.version.isEmpty,
              !value.executable.isEmpty, !value.executable.hasPrefix("/"),
              !value.executable.split(separator: "/").contains("..") else {
            throw PluginError.message("Invalid plugin ID, keyword, executable, or metadata.")
        }
        guard value.apiVersion == PluginProtocol.version else {
            throw PluginError.message("Unsupported plugin API version \(value.apiVersion).")
        }
        guard value.services.allSatisfy({ PluginProtocol.services.contains($0) }) else {
            throw PluginError.message("Unsupported host service.")
        }
        return value
    }
}

public struct PluginSetting: Codable, Sendable, Equatable {
    public var id: String
    public var enabled: Bool

    public init(id: String, enabled: Bool) { self.id = id; self.enabled = enabled }
}

public struct PluginPackage: Sendable, Equatable {
    public let manifest: PluginManifest
    public let directory: URL
    public let bundled: Bool
    public var executable: URL { directory.appendingPathComponent(manifest.executable) }

    public init(manifest: PluginManifest, directory: URL, bundled: Bool) {
        self.manifest = manifest; self.directory = directory; self.bundled = bundled
    }

    public func isEnabled(settings: [PluginSetting]) -> Bool {
        settings.first { $0.id == manifest.id }?.enabled ?? bundled
    }

    public func query(from fullQuery: String) -> String? {
        let parts = fullQuery.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
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

    public static func scan(bundled: URL?, user: URL) -> PluginDiscovery {
        var errors: [String] = []
        func read(_ root: URL?, bundled: Bool) -> [String: PluginPackage] {
            guard let root, FileManager.default.fileExists(atPath: root.path) else { return [:] }
            var packages: [String: PluginPackage] = [:]
            var duplicateIDs = Set<String>()
            do {
                let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                for folder in folders.sorted(by: { $0.path < $1.path }) {
                    let file = folder.appendingPathComponent("plugin.toml")
                    guard FileManager.default.fileExists(atPath: file.path) else { continue }
                    do {
                        let manifest = try PluginManifest.parse(String(contentsOf: file, encoding: .utf8))
                        let package = PluginPackage(manifest: manifest, directory: folder, bundled: bundled)
                        guard FileManager.default.isExecutableFile(atPath: package.executable.path) else {
                            throw PluginError.message("Missing or non-executable provider: \(manifest.executable)")
                        }
                        if packages[manifest.id] != nil { duplicateIDs.insert(manifest.id) }
                        packages[manifest.id] = package
                    } catch { errors.append("\(folder.lastPathComponent): \(error)") }
                }
            } catch { errors.append("\(root.path): \(error)") }
            for id in duplicateIDs {
                packages.removeValue(forKey: id)
                errors.append("Ambiguous plugin ID '\(id)' in \(root.path).")
            }
            return packages
        }
        let shipped = read(bundled, bundled: true)
        let installed = read(user, bundled: false)
        let merged = shipped.merging(installed) { _, user in user }
        return PluginDiscovery(packages: merged.values.sorted { $0.manifest.id < $1.manifest.id }, errors: errors)
    }
}
