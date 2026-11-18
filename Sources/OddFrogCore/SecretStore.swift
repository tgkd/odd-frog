import Foundation
import Synchronization

public struct SecretReference: Sendable, Hashable {
    public let source: String
    public let pluginID: String
    public let key: String

    public init(source: String, pluginID: String, key: String) {
        self.source = source
        self.pluginID = pluginID
        self.key = key
    }

    public init(package: PluginPackage, key: String) {
        self.init(source: package.source, pluginID: package.manifest.id, key: key)
    }

    public var account: String {
        "\(source)#\(pluginID)#\(key)"
    }
}

public protocol SecretStore: Sendable {
    func contains(_ reference: SecretReference) -> Bool
    func read(_ reference: SecretReference) throws -> String?
    func write(_ value: String, for reference: SecretReference) throws
    func remove(_ reference: SecretReference) throws
}

public final class MemorySecretStore: SecretStore {
    private let values = Mutex<[SecretReference: String]>([:])

    public init() {}

    public func contains(_ reference: SecretReference) -> Bool {
        values.withLock { $0[reference] != nil }
    }

    public func read(_ reference: SecretReference) throws -> String? {
        values.withLock { $0[reference] }
    }

    public func write(_ value: String, for reference: SecretReference) throws {
        values.withLock { $0[reference] = value }
    }

    public func remove(_ reference: SecretReference) throws {
        values.withLock { $0[reference] = nil }
    }
}

public enum SecretMigration {
    public static func extract(from settings: [PluginSetting], packages: [PluginPackage])
        -> (settings: [PluginSetting], secrets: [SecretReference: String]) {
        var result = settings
        var secrets: [SecretReference: String] = [:]
        for package in packages {
            guard let current = package.setting(in: result),
                  let index = result.firstIndex(of: current),
                  var values = result[index].values else { continue }
            let keys = package.manifest.settings.filter { $0.type == .secret }.map(\.key).filter { values[$0] != nil }
            guard !keys.isEmpty else { continue }
            for key in keys {
                if let value = values.removeValue(forKey: key)?.string, !value.isEmpty {
                    secrets[SecretReference(package: package, key: key)] = value
                }
            }
            result[index].values = values.isEmpty ? nil : values
        }
        return (result, secrets)
    }
}
