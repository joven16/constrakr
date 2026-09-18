//
//  DeviceTrackingMetadata.swift
//  ConsTrakr
//

import Foundation

enum DeviceTrackingMetadata {
    private static let defaults = UserDefaults.standard

    static var lastCollectMillis: Int64 {
        get { Int64(defaults.integer(forKey: Keys.lastCollect)) }
        set { defaults.set(Int(newValue), forKey: Keys.lastCollect) }
    }

    static var lastSuccessfulSyncMillis: Int64 {
        get { Int64(defaults.integer(forKey: Keys.lastSync)) }
        set { defaults.set(Int(newValue), forKey: Keys.lastSync) }
    }

    static var lastLocationMillis: Int64 {
        get { Int64(defaults.integer(forKey: Keys.lastLocation)) }
        set { defaults.set(Int(newValue), forKey: Keys.lastLocation) }
    }

    static var lastLocationLat: Double? {
        get {
            let value = defaults.double(forKey: Keys.lastLat)
            return value == 0 ? nil : value
        }
        set { defaults.set(newValue ?? 0, forKey: Keys.lastLat) }
    }

    static var lastLocationLng: Double? {
        get {
            let value = defaults.double(forKey: Keys.lastLng)
            return value == 0 ? nil : value
        }
        set { defaults.set(newValue ?? 0, forKey: Keys.lastLng) }
    }

    static var lastLocationAccuracy: Float? {
        get {
            let value = defaults.float(forKey: Keys.lastAccuracy)
            return value <= 0 ? nil : value
        }
        set { defaults.set(newValue ?? 0, forKey: Keys.lastAccuracy) }
    }

    private enum Keys {
        static let lastCollect = "deviceTracking.lastCollect"
        static let lastSync = "deviceTracking.lastSync"
        static let lastLocation = "deviceTracking.lastLocation"
        static let lastLat = "deviceTracking.lastLat"
        static let lastLng = "deviceTracking.lastLng"
        static let lastAccuracy = "deviceTracking.lastAccuracy"
    }
}
