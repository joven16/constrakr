//
//  SyncSettings.swift
//  ConsTrakr
//
//  User-configurable sync interval (foreground timer + iOS background refresh).
//

import Foundation

enum SyncSettings {
    static let defaultIntervalMinutes = 5
    static let minIntervalMinutes = 3
    static let maxIntervalMinutes = 60

    static var intervalMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: AppConstants.UserDefaultsKeys.syncIntervalMinutes)
            if stored == 0 { return defaultIntervalMinutes }
            return min(max(stored, minIntervalMinutes), maxIntervalMinutes)
        }
        set {
            let clamped = min(max(newValue, minIntervalMinutes), maxIntervalMinutes)
            UserDefaults.standard.set(clamped, forKey: AppConstants.UserDefaultsKeys.syncIntervalMinutes)
        }
    }

    static var intervalSeconds: TimeInterval {
        TimeInterval(intervalMinutes * 60)
    }

    static var intervalLabel: String {
        intervalMinutes == 1 ? "1 minute" : "\(intervalMinutes) minutes"
    }

    static var uploadLargeFilesOnWiFiOnly: Bool {
        get {
            UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.uploadLargeFilesOnWiFiOnly) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.uploadLargeFilesOnWiFiOnly)
        }
    }

    static var lastFullRosterSyncDate: Date? {
        let raw = UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.lastFullRosterSyncAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func recordFullRosterSync(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: AppConstants.UserDefaultsKeys.lastFullRosterSyncAt)
    }

    static var lastAttendanceVoidReconcileDate: Date? {
        let raw = UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.lastAttendanceVoidReconcileAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func recordAttendanceVoidReconcile(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: AppConstants.UserDefaultsKeys.lastAttendanceVoidReconcileAt)
    }
}
