//
//  KeychainStore.swift
//  Kanjiyomi
//

import Foundation
import Security

/// Keychain-backed storage for the one secret this app holds, the user's own API key.
///
/// `UserDefaults` would put the key in a plist inside the app container, where anything
/// with file access can read it and where it would travel into unencrypted backups. The
/// Keychain keeps it encrypted at rest and lets the accessibility class below decide when
/// and where it can be read at all.
nonisolated enum KeychainStore {
    enum Key: String {
        case openAIAPIKey = "openai.apiKey"
    }

    private static let service = "my.kanji.Kanjiyomi.secrets"

    /// - `ThisDeviceOnly` keeps the key out of backups and off any restored or migrated
    ///   device, so a leaked backup cannot spend the user's credit.
    /// - `WhenUnlocked` means a locked phone cannot be made to read it.
    /// Neither is the default, and both matter for a credential that costs money.
    private static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    static func save(_ value: String, for key: Key) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            delete(key)
            return
        }

        // Delete first so a re-save cannot inherit the attributes of an older item.
        delete(key)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func contains(_ key: Key) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: Key) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private static func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            // Explicit even though it is the default: this must never reach iCloud Keychain.
            kSecAttrSynchronizable as String: false
        ]
    }
}
