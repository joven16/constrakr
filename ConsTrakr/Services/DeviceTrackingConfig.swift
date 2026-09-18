//
//  DeviceTrackingConfig.swift
//  ConsTrakr
//

import Foundation

/// Admin-controlled fleet tracking preferences (Android parity).
enum DeviceTrackingConfig {
    private static let defaults = UserDefaults.standard

    static var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            notifyChanged()
        }
    }

    static var normalIntervalMinutes: Int {
        get {
            let stored = defaults.object(forKey: Keys.normalInterval) as? Int
            return max(minIntervalMinutes, stored ?? 30)
        }
        set {
            defaults.set(max(minIntervalMinutes, newValue), forKey: Keys.normalInterval)
            notifyChanged()
        }
    }

    static var activeIntervalMinutes: Int {
        get {
            let stored = defaults.object(forKey: Keys.activeInterval) as? Int
            return max(minIntervalMinutes, stored ?? 15)
        }
        set {
            defaults.set(max(minIntervalMinutes, newValue), forKey: Keys.activeInterval)
            notifyChanged()
        }
    }

    static let minIntervalMinutes = 15

    /// Fleet map pin — phone GPS is rarely ≤5 m unless outdoors; match geofence (~100 m).
    static let maxGPSAccuracyMeters: Double = 100

    static func intervalMillis(charging: Bool) -> Int {
        let minutes = charging ? activeIntervalMinutes : normalIntervalMinutes
        return max(minIntervalMinutes, minutes) * 60_000
    }

    private enum Keys {
        static let enabled = "deviceTracking.enabled"
        static let normalInterval = "deviceTracking.normalIntervalMin"
        static let activeInterval = "deviceTracking.activeIntervalMin"
    }

    private static func notifyChanged() {
        NotificationCenter.default.post(name: .deviceTrackingConfigDidChange, object: nil)
        Task { @MainActor in
            DeviceTrackingCoordinator.restart()
        }
    }
}

extension Notification.Name {
    static let deviceTrackingConfigDidChange = Notification.Name("deviceTracking.configDidChange")
}
