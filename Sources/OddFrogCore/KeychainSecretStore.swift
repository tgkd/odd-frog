import Foundation
import Security

public struct KeychainSecretStore: SecretStore {
    public static let defaultService = "com.paveltrofimov.odd-frog.plugin-secrets"

    public let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    public func contains(_ reference: SecretReference) -> Bool {
        false
    }

    public func read(_ reference: SecretReference) throws -> String? {
        nil
    }

    public func write(_ value: String, for reference: SecretReference) throws {
        throw PluginError.message("The Keychain store is not available.")
    }

    public func remove(_ reference: SecretReference) throws {
        throw PluginError.message("The Keychain store is not available.")
    }
}
