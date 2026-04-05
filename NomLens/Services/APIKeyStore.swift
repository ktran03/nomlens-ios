import Foundation
import Security

/// Persists the Claude API key in the iOS Keychain.
///
/// Priority order when reading:
/// 1. Keychain (user-entered via Settings)
/// 2. App bundle `CLAUDE_API_KEY` (set via Config.xcconfig — developer builds only)
enum APIKeyStore {

    private static let service = "com.nomlens.app"
    private static let account = "claude-api-key"

    // MARK: - Public API

    /// The active API key, or nil if none is configured.
    static var key: String? {
        if let stored = keychainKey, !stored.isEmpty { return stored }
        // Fall back to bundle (Config.xcconfig, stripped in release for public builds)
        let bundleKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        return bundleKey?.isEmpty == false ? bundleKey : nil
    }

    static var isSet: Bool { key != nil }

    /// Saves `key` to the Keychain, replacing any existing value.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)

        let attrs: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the stored key from the Keychain.
    @discardableResult
    static func delete() -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private static var keychainKey: String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
