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

    /// Stored device label — required before sync pushes to the web Devices list.
    static var customName: String {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.deviceCustomName) ?? ""
    }

    static var hasDeviceName: Bool {
        !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Name pushed to the web Devices list on sync.
    static var syncName: String {
        ensureDeviceNameSeeded()
        return customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Seeds the field once from the iOS device name when unset — user must keep or edit it in Settings.
    static func ensureDeviceNameSeeded() {
        guard !hasDeviceName else { return }
        let system = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !system.isEmpty else { return }
        UserDefaults.standard.set(String(system.prefix(200)), forKey: AppConstants.UserDefaultsKeys.deviceCustomName)
    }

    @discardableResult
    static func setSyncName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        UserDefaults.standard.set(String(trimmed.prefix(200)), forKey: AppConstants.UserDefaultsKeys.deviceCustomName)
        postChange()
        return true
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
