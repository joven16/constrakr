//
//  DeviceStore.swift
//  ConsTrakr
//

import Foundation
import UIKit

enum DeviceStore {
    static let deviceDidChangeNotification = Notification.Name("constrakr.deviceDidChange")

    static var localId: UUID {
        if let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.deviceLocalId),
           let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: AppConstants.UserDefaultsKeys.deviceLocalId)
        return id
    }

    static var assignedUserName: String? {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserName)
    }

    static var assignedUserUsername: String? {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserUsername)
    }

    static var adminCodeRequired: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.deviceAdminCodeRequired)
    }

    /// Name from Settings → General → About on this iPhone/iPad.
    static var systemDeviceName: String {
        UIDevice.current.name
    }

    /// Optional label set in ConsTrakr — empty when using the system device name.
    static var customName: String {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.deviceCustomName) ?? ""
    }

    static var usesCustomName: Bool {
        !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Name pushed to the web Devices list on sync.
    static var syncName: String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return String(custom.prefix(200))
        }
        return systemDeviceName
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func setSyncName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = systemDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == system {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.deviceCustomName)
        } else {
            UserDefaults.standard.set(String(trimmed.prefix(200)), forKey: AppConstants.UserDefaultsKeys.deviceCustomName)
        }
        postChange()
    }

    static func resetToSystemDeviceName() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.deviceCustomName)
        postChange()
    }

    static func update(from device: DeviceDTO?) {
        if let device {
            UserDefaults.standard.set(device.assignedUserName, forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserName)
            UserDefaults.standard.set(device.assignedUserUsername, forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserUsername)
            UserDefaults.standard.set(device.adminCodeRequired, forKey: AppConstants.UserDefaultsKeys.deviceAdminCodeRequired)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserName)
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserUsername)
            UserDefaults.standard.set(false, forKey: AppConstants.UserDefaultsKeys.deviceAdminCodeRequired)
        }
        postChange()
    }

    private static func postChange() {
        NotificationCenter.default.post(name: deviceDidChangeNotification, object: nil)
    }
}
