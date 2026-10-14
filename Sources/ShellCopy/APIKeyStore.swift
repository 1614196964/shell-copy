import Foundation
import Security
import ShellCopyCore

/// Credentials live in the user's login keychain, never in UserDefaults or the app bundle.
enum APIKeyStore {
    static func service(for provider: CloudProvider) -> String {
        // The original Jev identifier must remain stable across upgrades.
        "local.shell-copy.app." + (provider == .jev ? "typesafe" : "bjev")
    }

    private static func query(for provider: CloudProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service(for: provider),
         kSecAttrAccount as String: "api-key"]
    }

    static func load(for provider: CloudProvider) throws -> String? {
        var request = query(for: provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }

    static func save(_ key: String, for provider: CloudProvider) throws {
        let query = query(for: provider)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func remove(for provider: CloudProvider) throws {
        let status = SecItemDelete(query(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Unable to access the macOS keychain (error \(status))." }
    }
}
