//
//  AppAccessSession.swift
//  ConsTrakr
//
//  Operator (default): scan + view one site; add/edit employees on that site.
//  Admin unlock (6-digit code): job sites, settings, delete employees, any-site edits.
//

import Foundation

@MainActor
@Observable
final class AppAccessSession {
    static let shared = AppAccessSession()
    static let sessionDidChangeNotification = Notification.Name("constrakr.appAccessSessionDidChange")
    static let unlockDuration: TimeInterval = 15 * 60

    private(set) var unlockedUntil: Date?
    private(set) var unlockedOperatorName: String?
    /// Admin-only filter for Dashboard / Employees / DTR (does not change default site or scanner GPS).
    private(set) var adminViewSiteId: UUID?

    var selectableSites: [JobSite] {
        JobSiteStore.allSites.filter(\.hasCoordinate)
    }

    /// Site used to filter Dashboard, Employees, and DTR.
    var effectiveViewSiteId: UUID? {
        if isAdminUnlocked {
            if let adminViewSiteId, JobSiteStore.site(id: adminViewSiteId) != nil {
                return adminViewSiteId
            }
            return operatorSiteId
        }
        return operatorSiteId
    }

    var effectiveViewSiteTitle: String? {
        guard let effectiveViewSiteId, let site = JobSiteStore.site(id: effectiveViewSiteId) else { return nil }
        return site.displayTitle
    }

    var isViewingNonDefaultSite: Bool {
        guard isAdminUnlocked,
              let effectiveViewSiteId,
              let operatorSiteId
        else { return false }
        return effectiveViewSiteId != operatorSiteId
    }

    func setAdminViewSite(_ siteId: UUID) {
        adminViewSiteId = siteId
        postChange()
    }

    func resetAdminViewSite() {
        adminViewSiteId = nil
        postChange()
    }

    var isAdminUnlocked: Bool {
        guard let unlockedUntil else { return false }
        if Date() >= unlockedUntil {
            lock()
            return false
        }
        return true
    }

    var operatorSiteId: UUID? {
        JobSiteStore.defaultSiteId ?? JobSiteStore.defaultSite?.id
    }

    var operatorSiteTitle: String? {
        guard let operatorSiteId, let site = JobSiteStore.site(id: operatorSiteId) else { return nil }
        return site.displayTitle
    }

    func unlock(operatorName: String?) {
        unlockedUntil = Date().addingTimeInterval(Self.unlockDuration)
        unlockedOperatorName = operatorName
        postChange()
    }

    func lock() {
        unlockedUntil = nil
        unlockedOperatorName = nil
        adminViewSiteId = nil
        postChange()
    }

    @discardableResult
    func refreshExpiryIfNeeded() -> Bool {
        isAdminUnlocked
    }

    func canRegisterEmployee() -> Bool {
        operatorSiteId != nil && !DeviceAccessGuard.isBlocked
    }

    func canEditEmployee(_ employee: Employee) -> Bool {
        guard let siteId = operatorSiteId else { return false }
        if isAdminUnlocked { return true }
        if employee.assignedSiteId == siteId { return true }
        if employee.assignedSiteId == nil { return true }
        return false
    }

    func canDeleteEmployees() -> Bool {
        isAdminUnlocked
    }

    func canManageJobSites() -> Bool {
        isAdminUnlocked
    }

    func canAccessAdminSettings() -> Bool {
        isAdminUnlocked
    }

    func shouldRequireAdminCodeForSensitiveEdits() -> Bool {
        !isAdminUnlocked
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
    }
}
