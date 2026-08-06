//
//  SyncAuthStore.swift
//  ConsTrakr
//
//  Persists IMS admin JWT for auto-sync across app launches.
//

import Foundation
import Security

enum SyncAuthStore {
    private static let service = "com.constrakr.sync-auth"
    private static let tokenAccount = "access-token"
    private static let usernameKey = "sync.adminUsername"

    static func saveSession(token: String, username: String) {
        saveToken(token)
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    static func loadToken() -> String? {
        loadKeychain(account: tokenAccount)
    }

    static func loadUsername() -> String? {
        UserDefaults.standard.string(forKey: usernameKey)
    }

    static func clear() {
        deleteKeychain(account: tokenAccount)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    private static func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        deleteKeychain(account: tokenAccount)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
