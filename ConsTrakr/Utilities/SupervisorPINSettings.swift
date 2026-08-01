//
//  SupervisorPINSettings.swift
//  ConsTrakr
//
// Optional supervisor PIN required before Time In / Time Out (buddy-punch deterrent).
//

import CryptoKit
import Foundation

enum SupervisorPINSettings {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.supervisorPINEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.supervisorPINEnabled) }
    }

    static var hasPIN: Bool {
        !(storedHash ?? "").isEmpty
    }

    /// True when PIN gate should block starting a scan.
    static var isRequired: Bool {
        isEnabled && hasPIN
    }

    static func setPIN(_ pin: String) -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= 12, trimmed.allSatisfy(\.isNumber) else {
            return false
        }
        UserDefaults.standard.set(hash(trimmed), forKey: AppConstants.UserDefaultsKeys.supervisorPINHash)
        isEnabled = true
        return true
    }

    static func clearPIN() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.supervisorPINHash)
        isEnabled = false
    }

    static func verify(_ pin: String) -> Bool {
        guard isRequired else { return true }
        return hash(pin) == storedHash
    }

    private static var storedHash: String? {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.supervisorPINHash)
    }

    private static func hash(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(pin.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
