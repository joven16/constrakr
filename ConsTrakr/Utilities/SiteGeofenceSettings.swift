//
//  SiteGeofenceSettings.swift
//  ConsTrakr
//
// Optional job-site geofence — punches only allowed near the configured location.
//

import CoreLocation
import Foundation

enum SiteGeofenceSettings {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.siteGeofenceEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.siteGeofenceEnabled) }
    }

    static var latitude: Double {
        get { UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.siteLatitude) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.siteLatitude) }
    }

    static var longitude: Double {
        get { UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.siteLongitude) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.siteLongitude) }
    }

    /// Meters from site center allowed for a punch.
    static var radiusMeters: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.siteRadiusMeters)
            return stored > 0 ? stored : 150
        }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.siteRadiusMeters) }
    }

    static var hasSiteCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    static var isRequired: Bool {
        isEnabled && hasSiteCoordinate
    }

    static var siteCoordinate: CLLocationCoordinate2D? {
        guard hasSiteCoordinate else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func setSite(coordinate: CLLocationCoordinate2D, radiusMeters: Double = 150) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.radiusMeters = max(50, radiusMeters)
        isEnabled = true
    }

    static func clearSite() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.siteLatitude)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.siteLongitude)
        isEnabled = false
    }
}
