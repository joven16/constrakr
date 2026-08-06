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
    private static let tokenExpiresAtKey = "sync.tokenExpiresAt"

    static func saveSession(token: String, username: String, expiresIn: Int? = nil) {
        saveToken(token)
        UserDefaults.standard.set(username, forKey: usernameKey)
        if let expiresIn, expiresIn > 0 {
            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: tokenExpiresAtKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tokenExpiresAtKey)
        }
    }

    static func isTokenExpired(leeway seconds: TimeInterval = 120) -> Bool {
        let expiresAt = UserDefaults.standard.double(forKey: tokenExpiresAtKey)
        guard expiresAt > 0 else { return false }
        return Date().timeIntervalSince1970 >= expiresAt - seconds
    }

    static func tokenExpiryDescription() -> String? {
        let expiresAt = UserDefaults.standard.double(forKey: tokenExpiresAtKey)
        guard expiresAt > 0 else { return nil }
        return Date(timeIntervalSince1970: expiresAt).formatted(date: .omitted, time: .shortened)
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
        UserDefaults.standard.removeObject(forKey: tokenExpiresAtKey)
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
