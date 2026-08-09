//
//  ScannerTabSettings.swift
//  ConsTrakr
//
//  Admin-only preference to hide the scanner tab while monitoring.
//

import Foundation

enum ScannerTabSettings {
    static let didChangeNotification = Notification.Name("constrakr.scannerTabSettingsDidChange")

    static var isEnabledForAdmin: Bool {
        get {
            if UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.adminScannerTabEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.adminScannerTabEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.adminScannerTabEnabled)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
