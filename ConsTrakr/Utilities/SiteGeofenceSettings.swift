//
//  SiteGeofenceSettings.swift
//  ConsTrakr
//
// Global on-site GPS toggle and legacy single-site keys (migrated into JobSiteStore).
//

import CoreLocation
import Foundation

enum SiteGeofenceSettings {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.siteGeofenceEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaultsKeys.siteGeofenceEnabled) }
    }

    // MARK: Legacy keys (read-only for migration)

    static var legacyLatitude: Double {
        UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.siteLatitude)
    }

    static var legacyLongitude: Double {
        UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.siteLongitude)
    }

    static var legacyRadiusMeters: Double {
        let stored = UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.siteRadiusMeters)
        return stored > 0 ? stored : 100
    }

    static var legacyHasSiteCoordinate: Bool {
        legacyLatitude != 0 || legacyLongitude != 0
    }

    // MARK: Default site (from JobSiteStore)

    static var hasSiteCoordinate: Bool {
        JobSiteStore.defaultSite?.hasCoordinate == true
    }

    static var isRequired: Bool {
        isEnabled && hasSiteCoordinate
    }

    static var siteCoordinate: CLLocationCoordinate2D? {
        JobSiteStore.defaultSite?.coordinate
    }

    static var radiusMeters: Double {
        get { JobSiteStore.defaultSite?.radiusMeters ?? 100 }
        set {
            guard var site = JobSiteStore.defaultSite else { return }
            site.radiusMeters = JobSite.clampedRadius(newValue)
            JobSiteStore.upsert(site)
        }
    }

    static var defaultSiteName: String {
        JobSiteStore.defaultSite?.displayTitle ?? "Job site"
    }

    static func clearSite() {
        isEnabled = false
    }
}
