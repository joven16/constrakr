//
//  JobSiteStore.swift
//  ConsTrakr
//

import CoreLocation
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

    static var pendingDeleteIds: [UUID] {
        guard let raw = UserDefaults.standard.stringArray(forKey: AppConstants.UserDefaultsKeys.pendingJobSiteDeletions) else {
            return []
        }
        return raw.compactMap(UUID.init(uuidString:))
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

    /// Job site that must match GPS for this employee's punch (assigned site only — no default fallback).
    static func assignedSite(for employeeAssignedSiteId: UUID?) -> JobSite? {
        guard let employeeAssignedSiteId,
              let site = site(id: employeeAssignedSiteId),
              site.hasCoordinate
        else { return nil }
        return site
    }

    /// Resolves which geofence applies at punch time.
    static func attendanceSite(for employee: Employee) -> JobSite? {
        if let assigned = assignedSite(for: employee.assignedSiteId) {
            return assigned
        }
        if SiteGeofenceSettings.isRequired {
            return defaultSite
        }
        return nil
    }

    /// Nearest configured site whose radius contains the given GPS fix.
    static func siteContaining(location: CLLocation) -> JobSite? {
        var match: (site: JobSite, distance: CLLocationDistance)?
        for site in allSites where site.hasCoordinate {
            let siteLocation = CLLocation(latitude: site.latitude, longitude: site.longitude)
            let distance = location.distance(from: siteLocation)
            guard distance <= site.radiusMeters else { continue }
            if match == nil || distance < match!.distance {
                match = (site, distance)
            }
        }
        return match?.site
    }

    static var hasConfiguredSites: Bool {
        allSites.contains(where: \.hasCoordinate)
    }

    @discardableResult
    static func upsert(_ site: JobSite, touchUpdatedAt: Bool = true) -> JobSite {
        migrateLegacyIfNeeded()
        var updated = site
        if touchUpdatedAt {
            updated.updatedAt = Date()
        }
        var sites = allSites
        if let index = sites.firstIndex(where: { $0.id == updated.id }) {
            sites[index] = updated
        } else {
            sites.append(updated)
        }
        persist(sites)
        if defaultSiteId == nil, updated.hasCoordinate {
            defaultSiteId = updated.id
        }
        return updated
    }

    static func delete(id: UUID, recordPendingSync: Bool = true) {
        if recordPendingSync {
            var pending = pendingDeleteIds
            if !pending.contains(id) {
                pending.append(id)
                UserDefaults.standard.set(
                    pending.map(\.uuidString),
                    forKey: AppConstants.UserDefaultsKeys.pendingJobSiteDeletions
                )
            }
        }
        let sites = allSites.filter { $0.id != id }
        persist(sites)
        if defaultSiteId == id {
            defaultSiteId = sites.first(where: \.hasCoordinate)?.id
        }
    }

    static func clearPendingDelete(id: UUID) {
        let remaining = pendingDeleteIds.filter { $0 != id }
        UserDefaults.standard.set(
            remaining.map(\.uuidString),
            forKey: AppConstants.UserDefaultsKeys.pendingJobSiteDeletions
        )
    }

    static func setDefaultSite(id: UUID) {
        guard site(id: id) != nil else { return }
        defaultSiteId = id
    }

    static func syncFields(for assignedSiteId: UUID?) -> (id: UUID?, name: String?, location: String?) {
        guard let assignedSiteId, let site = site(id: assignedSiteId) else {
            return (nil, nil, nil)
        }
        let location = site.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return (assignedSiteId, site.displayTitle, location.isEmpty ? nil : location)
    }

    /// Ensures a catalog row exists when employee sync references a site not yet on device.
    static func ensureFromEmployeeAssignment(id: UUID?, name: String?, location: String?) {
        guard let id else { return }
        if site(id: id) != nil { return }
        let stub = JobSite(
            id: id,
            name: (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed site" : (name ?? "Unnamed site"),
            locationLabel: location ?? "",
            latitude: 0,
            longitude: 0,
            radiusMeters: 150,
            updatedAt: .distantPast
        )
        upsert(stub, touchUpdatedAt: false)
    }

    static func sitesNeedingUpload(comparedTo remote: [JobSiteDTO]) -> [JobSite] {
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        return allSites.filter { site in
            guard let remote = remoteById[site.id] else { return true }
            let remoteUpdated = remote.updatedAt ?? .distantPast
            return site.updatedAt > remoteUpdated
        }
    }

    static func applyRemoteCatalog(_ remoteSites: [JobSiteDTO]) {
        let remoteIds = Set(remoteSites.map(\.id))
        let lastRemote = Set(lastKnownRemoteIds())

        for dto in remoteSites {
            let remoteSite = dto.toJobSite()
            if let local = site(id: dto.id) {
                let remoteUpdated = dto.updatedAt ?? .distantPast
                if remoteUpdated >= local.updatedAt {
                    upsert(remoteSite, touchUpdatedAt: false)
                }
            } else {
                upsert(remoteSite, touchUpdatedAt: false)
            }
        }

        for local in allSites {
            if lastRemote.contains(local.id), !remoteIds.contains(local.id) {
                deleteLocalOnly(id: local.id)
            }
        }

        saveLastKnownRemoteIds(remoteSites.map(\.id))
    }

    private static func deleteLocalOnly(id: UUID) {
        let sites = allSites.filter { $0.id != id }
        persist(sites)
        if defaultSiteId == id {
            defaultSiteId = sites.first(where: \.hasCoordinate)?.id
        }
    }

    private static func lastKnownRemoteIds() -> [UUID] {
        guard let raw = UserDefaults.standard.stringArray(forKey: AppConstants.UserDefaultsKeys.lastRemoteJobSiteIds) else {
            return []
        }
        return raw.compactMap(UUID.init(uuidString:))
    }

    private static func saveLastKnownRemoteIds(_ ids: [UUID]) {
        UserDefaults.standard.set(
            ids.map(\.uuidString),
            forKey: AppConstants.UserDefaultsKeys.lastRemoteJobSiteIds
        )
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
