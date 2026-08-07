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

    /// App-wide site selected in Settings / Job Sites (scanner "current site").
    static func currentOperatingSiteId() -> UUID? {
        if let id = defaultSiteId { return id }
        return defaultSite?.id
    }

    static func currentOperatingSiteLabel() -> String {
        if let id = currentOperatingSiteId() {
            return assignedSiteLabel(for: id)
        }
        return "Current site"
    }

    static func site(id: UUID?) -> JobSite? {
        guard let id else { return nil }
        return allSites.first { $0.id == id }
    }

    static func site(for employeeAssignedSiteId: UUID?) -> JobSite? {
        guard let employeeAssignedSiteId else { return defaultSite }
        return site(id: employeeAssignedSiteId)
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
        if employee.assignedSiteId != nil {
            return assignedSite(for: employee.assignedSiteId)
        }
        if SiteGeofenceSettings.isRequired {
            return defaultSite
        }
        return nil
    }

    /// Display name for an assigned site id (catalog row may lack GPS pin).
    static func assignedSiteLabel(for siteId: UUID?, fallbackName: String? = nil) -> String {
        if let siteId, let site = site(id: siteId) {
            return site.displayTitle
        }
        let trimmed = (fallbackName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Assigned site"
    }

    static func applyAssignmentSnapshot(
        to employee: Employee,
        siteId: UUID?,
        name: String?,
        location: String?
    ) {
        var resolvedId = siteId
        if let match = findMatchingSite(name: name, location: location) {
            if siteId == nil || siteId != match.id {
                resolvedId = match.id
            }
        } else if let siteId, site(id: siteId) == nil {
            ensureFromEmployeeAssignment(
                id: siteId,
                name: name,
                location: location
            )
        }

        employee.assignedSiteId = resolvedId
        employee.assignedSiteName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        employee.assignedSiteLocation = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        if findMatchingSite(name: name, location: location) != nil { return }
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

    /// Collapses duplicate catalog rows that share the same name + location label.
    @discardableResult
    static func deduplicateCatalog() -> [UUID: UUID] {
        migrateLegacyIfNeeded()
        let sites = allSites
        var groups: [String: [JobSite]] = [:]
        for site in sites {
            let key = normalizedKey(name: site.name, location: site.locationLabel)
            groups[key, default: []].append(site)
        }

        var remap: [UUID: UUID] = [:]
        var kept: [JobSite] = []
        for group in groups.values {
            guard let first = group.first else { continue }
            let canonical = group.dropFirst().reduce(first, preferSite)
            kept.append(canonical)
            for site in group where site.id != canonical.id {
                remap[site.id] = canonical.id
            }
        }

        kept.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        if remap.isEmpty, kept.count == sites.count { return [:] }

        persist(kept)
        if let defaultId = defaultSiteId, let newId = remap[defaultId] {
            defaultSiteId = newId
        }
        return remap
    }

    static func findMatchingSite(name: String?, location: String?) -> JobSite? {
        let key = normalizedKey(name: name ?? "", location: location ?? "")
        return allSites.first {
            normalizedKey(name: $0.name, location: $0.locationLabel) == key
        }
    }

    static func remapSiteId(from oldId: UUID, to newId: UUID) {
        guard oldId != newId else { return }
        var sites = allSites.filter { $0.id != oldId }
        persist(sites)
        if defaultSiteId == oldId {
            defaultSiteId = newId
        }
    }

    private static func normalizedKey(name: String, location: String) -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedName)|\(normalizedLocation)"
    }

    private static func preferSite(_ a: JobSite, _ b: JobSite) -> JobSite {
        if a.hasCoordinate != b.hasCoordinate {
            return a.hasCoordinate ? a : b
        }
        if a.updatedAt != b.updatedAt {
            return a.updatedAt >= b.updatedAt ? a : b
        }
        return a
    }

    static func sitesNeedingUpload(comparedTo remote: [JobSiteDTO]) -> [JobSite] {
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        return allSites.filter { site in
            guard let remote = remoteById[site.id] else { return true }
            let remoteUpdated = remote.updatedAt ?? .distantPast
            if site.updatedAt > remoteUpdated { return true }
            let remoteLocation = (remote.locationLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let localLocation = site.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return site.displayTitle != remote.name
                || localLocation != remoteLocation
                || site.latitude != remote.latitude
                || site.longitude != remote.longitude
                || site.radiusMeters != remote.radiusMeters
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
