//
//  JobSiteStore.swift
//  ConsTrakr
//

import Foundation

enum JobSiteStore {
    static let sitesDidChangeNotification = Notification.Name("constrakr.jobSitesDidChange")

    private static var didMigrateLegacy = false

    static var allSites: [JobSite] {
        migrateLegacyIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.jobSitesJSON),
              let decoded = try? JSONDecoder().decode([JobSite].self, from: data)
        else { return [] }
        return decoded.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    static var defaultSiteId: UUID? {
        get {
            migrateLegacyIfNeeded()
            guard let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.defaultJobSiteId),
                  let id = UUID(uuidString: raw)
            else { return nil }
            return id
        }
        set {
            let currentRaw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.defaultJobSiteId)
            let newRaw = newValue?.uuidString
            if currentRaw == newRaw { return }

            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: AppConstants.UserDefaultsKeys.defaultJobSiteId)
            } else {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.defaultJobSiteId)
            }
            postChange()
        }
    }

    static var defaultSite: JobSite? {
        migrateLegacyIfNeeded()
        if let id = defaultSiteId, let site = site(id: id), site.hasCoordinate {
            return site
        }
        return allSites.first(where: { $0.hasCoordinate })
    }

    static func site(id: UUID?) -> JobSite? {
        guard let id else { return nil }
        return allSites.first { $0.id == id }
    }

    static func site(for employeeAssignedSiteId: UUID?) -> JobSite? {
        if let assigned = employeeAssignedSiteId, let site = site(id: assigned), site.hasCoordinate {
            return site
        }
        return defaultSite
    }

    static var hasConfiguredSites: Bool {
        allSites.contains(where: \.hasCoordinate)
    }

    @discardableResult
    static func upsert(_ site: JobSite) -> JobSite {
        migrateLegacyIfNeeded()
        var sites = allSites
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        } else {
            sites.append(site)
        }
        persist(sites)
        if defaultSiteId == nil, site.hasCoordinate {
            defaultSiteId = site.id
        }
        return site
    }

    static func delete(id: UUID) {
        let sites = allSites.filter { $0.id != id }
        persist(sites)
        if defaultSiteId == id {
            defaultSiteId = sites.first(where: \.hasCoordinate)?.id
        }
    }

    static func setDefaultSite(id: UUID) {
        guard site(id: id) != nil else { return }
        defaultSiteId = id
    }

    private static func persist(_ sites: [JobSite]) {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.jobSitesJSON)
        }
        postChange()
    }

    private static func postChange() {
        NotificationCenter.default.post(name: sitesDidChangeNotification, object: nil)
    }

    /// Imports the legacy single-site UserDefaults keys into the first JobSite row.
    private static func migrateLegacyIfNeeded() {
        guard !didMigrateLegacy else { return }
        didMigrateLegacy = true

        let hasStoredSites = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.jobSitesJSON) != nil
        if hasStoredSites { return }

        guard SiteGeofenceSettings.legacyHasSiteCoordinate else { return }

        let legacySite = JobSite(
            name: "Main Site",
            locationLabel: "",
            latitude: SiteGeofenceSettings.legacyLatitude,
            longitude: SiteGeofenceSettings.legacyLongitude,
            radiusMeters: SiteGeofenceSettings.legacyRadiusMeters
        )
        persist([legacySite])
        defaultSiteId = legacySite.id
    }
}
