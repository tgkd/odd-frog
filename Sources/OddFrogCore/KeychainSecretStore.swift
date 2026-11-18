import Foundation
import Security

public struct KeychainSecretStore: SecretStore {
    public static let defaultService = "com.paveltrofimov.odd-frog.plugin-secrets"

    public let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    public func contains(_ reference: SecretReference) -> Bool {
        var query = baseQuery(reference)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func read(_ reference: SecretReference) throws -> String? {
        var query = baseQuery(reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw PluginError.message("The Keychain item is not readable text.")
        }
        return value
    }

    public func write(_ value: String, for reference: SecretReference) throws {
        try remove(reference)
        var query = baseQuery(reference)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrLabel as String] = "Odd Frog plugin secret"
        try check(SecItemAdd(query as CFDictionary, nil))
    }

    public func remove(_ reference: SecretReference) throws {
        let status = SecItemDelete(baseQuery(reference) as CFDictionary)
        if status == errSecItemNotFound { return }
        try check(status)
    }

    private func baseQuery(_ reference: SecretReference) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: reference.account]
    }

    private func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        throw PluginError.message(text)
    }
}
