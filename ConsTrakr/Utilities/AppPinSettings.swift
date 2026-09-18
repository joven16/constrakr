//
//  AppPinSettings.swift
//  ConsTrakr
//

import CryptoKit
import Foundation

/// Local 6-digit app PIN — works offline (Android parity, no kiosk required).
enum AppPinSettings {
    static let pinLength = 6
    static let defaultPin = "882741"

    private static let defaults = UserDefaults.standard
    private static let hashKey = "appPin.hash"
    private static let saltKey = "appPin.salt"

    static var hasAppPin: Bool {
        defaults.string(forKey: hashKey) != nil
    }

    static func verify(_ pin: String) -> Bool {
        guard let hash = defaults.string(forKey: hashKey),
              let salt = defaults.string(forKey: saltKey) else { return false }
        return hash == hashPin(pin, salt: salt)
    }

    static func setPin(_ pin: String) {
        precondition(pin.count == pinLength && pin.allSatisfy(\.isNumber))
        let salt = UUID().uuidString
        defaults.set(salt, forKey: saltKey)
        defaults.set(hashPin(pin, salt: salt), forKey: hashKey)
    }

    static func ensureDefaultIfNeeded() {
        if !hasAppPin { setPin(defaultPin) }
    }

    static func clearPin() {
        defaults.removeObject(forKey: hashKey)
        defaults.removeObject(forKey: saltKey)
    }

    private static func hashPin(_ pin: String, salt: String) -> String {
        let input = Data((salt + pin).utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
