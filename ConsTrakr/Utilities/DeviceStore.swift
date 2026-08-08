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

    static var displayName: String {
        UIDevice.current.name
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
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
        NotificationCenter.default.post(name: deviceDidChangeNotification, object: nil)
    }
}
