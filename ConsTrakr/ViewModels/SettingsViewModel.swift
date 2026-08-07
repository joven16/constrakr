//
//  SettingsViewModel.swift
//  ConsTrakr
//
//  CHANGE: Admin sign-in + restore hooks for new-device offline bootstrap.
//

import Foundation
import SwiftData
import CoreLocation

@MainActor
@Observable
final class SettingsViewModel {
    var apiBaseURL: String {
        didSet {
            UserDefaults.standard.set(apiBaseURL, forKey: AppConstants.UserDefaultsKeys.apiBaseURL)
            Task { await APIService.shared.updateBaseURL(apiBaseURL) }
        }
    }

    var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled)
            if autoSyncEnabled {
                syncQueue?.startAutoSync()
                BackgroundSyncScheduler.scheduleNextSync()
            } else {
                syncQueue?.stopAutoSync()
            }
        }
    }

    var syncIntervalMinutes: Int {
        didSet {
            SyncSettings.intervalMinutes = syncIntervalMinutes
            if autoSyncEnabled {
                syncQueue?.startAutoSync()
                BackgroundSyncScheduler.scheduleNextSync()
            }
        }
    }

    var matchThreshold: Double {
        didSet {
            UserDefaults.standard.set(matchThreshold, forKey: AppConstants.UserDefaultsKeys.matchThreshold)
        }
    }

    /// Security: raw frames stay off unless explicitly enabled for debug / re-enrollment.
    var uploadRawFramesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(uploadRawFramesEnabled, forKey: AppConstants.UserDefaultsKeys.uploadRawFramesEnabled)
        }
    }

    var faceScanCenterEnabled = true {
        didSet {
            guard !isApplyingFaceScanBatch else { return }
            Task { await saveFaceScanStep(.closeUp, enabled: faceScanCenterEnabled) }
        }
    }

    var faceScanLeftEnabled = true {
        didSet {
            guard !isApplyingFaceScanBatch else { return }
            Task { await saveFaceScanStep(.lookLeft, enabled: faceScanLeftEnabled) }
        }
    }

    var faceScanRightEnabled = true {
        didSet {
            guard !isApplyingFaceScanBatch else { return }
            Task { await saveFaceScanStep(.lookRight, enabled: faceScanRightEnabled) }
        }
    }

    var faceScanUpEnabled = true {
        didSet {
            guard !isApplyingFaceScanBatch else { return }
            Task { await saveFaceScanStep(.lookUp, enabled: faceScanUpEnabled) }
        }
    }

    var faceScanDownEnabled = true {
        didSet {
            guard !isApplyingFaceScanBatch else { return }
            Task { await saveFaceScanStep(.lookDown, enabled: faceScanDownEnabled) }
        }
    }

    private(set) var faceScanSettingsMessage: String?
    private(set) var faceScanLevel: FaceScanSettings.Level?
    private(set) var isSavingFaceScanSettings = false
    private var isApplyingFaceScanBatch = false

    var supervisorPINEnabled: Bool {
        didSet {
            if supervisorPINEnabled && !SupervisorPINSettings.hasPIN {
                // Don't enable until a PIN is set.
                supervisorPINEnabled = false
                statusMessage = "Set a supervisor PIN first."
                return
            }
            SupervisorPINSettings.isEnabled = supervisorPINEnabled
        }
    }

    var newSupervisorPIN = ""
    var confirmSupervisorPIN = ""

    var siteGeofenceEnabled: Bool {
        didSet {
            if siteGeofenceEnabled && !JobSiteStore.hasConfiguredSites {
                siteGeofenceEnabled = false
                statusMessage = "Add a job site under More → Job Sites first."
                return
            }
            SiteGeofenceSettings.isEnabled = siteGeofenceEnabled
        }
    }

    var defaultJobSiteId: UUID?

    func setDefaultJobSiteId(_ id: UUID?) {
        guard !isSyncingDefaultSiteFromStore else { return }
        guard defaultJobSiteId != id else { return }
        defaultJobSiteId = id
        if JobSiteStore.defaultSiteId != id {
            JobSiteStore.defaultSiteId = id
        }
    }

    var configuredJobSites: [JobSite] {
        JobSiteStore.allSites.filter(\.hasCoordinate)
    }

    /// Picker-safe selection — always matches a configured site when sites exist.
    var effectiveDefaultSiteId: UUID? {
        if let defaultJobSiteId,
           configuredJobSites.contains(where: { $0.id == defaultJobSiteId }) {
            return defaultJobSiteId
        }
        return configuredJobSites.first?.id
    }

    private var isSyncingDefaultSiteFromStore = false

    var adminUsername = ""
    var adminPassword = ""

    private(set) var pendingCount = 0
    private(set) var lastSyncDate: Date?
    private(set) var isSyncing = false
    private(set) var isOnline = false
    private(set) var isAdminAuthenticated = false
    private(set) var statusMessage: String?

    private(set) var isTestingRestore = false
    var restoreTestMessage: String?
    var showRestoreTestAlert = false

    private var syncQueue: SyncQueue?

    init() {
        apiBaseURL = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiBaseURL)
            ?? AppConstants.apiBaseURL
        autoSyncEnabled = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled) as? Bool ?? true
        syncIntervalMinutes = SyncSettings.intervalMinutes
        matchThreshold = Double(MatchThresholdSettings.current)
        uploadRawFramesEnabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.uploadRawFramesEnabled)
        supervisorPINEnabled = SupervisorPINSettings.isRequired
        siteGeofenceEnabled = SiteGeofenceSettings.isRequired
        defaultJobSiteId = JobSiteStore.defaultSiteId
            ?? JobSiteStore.allSites.first(where: \.hasCoordinate)?.id
        reloadFaceScanPoseSettings()
    }

    /// Slider range depends on whether AdaFace or the handcrafted fallback is active.
    var matchThresholdRange: ClosedRange<Double> {
        CoreMLFaceRecognizer.shared.isReady ? 0.30...0.70 : 0.80...0.99
    }

    private(set) var isTestingAPI = false
    var apiTestResult: APITestResult?
    private(set) var apiTestMessage: String?
    var showAPITestAlert = false

    func configure(syncQueue: SyncQueue) {
        self.syncQueue = syncQueue
        refresh()
    }

    func refresh() {
        pendingCount = syncQueue?.pendingCount ?? 0
        lastSyncDate = syncQueue?.lastSyncDate
        isSyncing = syncQueue?.isSyncing ?? false
        isOnline = NetworkMonitor.shared.isConnected
        if adminUsername.isEmpty, let saved = SyncAuthStore.loadUsername() {
            adminUsername = saved
        }
        reloadFaceScanPoseSettings()
        syncDefaultJobSiteFromStore()
        statusMessage = resolvedSyncStatusMessage()
    }

    func reloadJobSiteSettings() {
        syncDefaultJobSiteFromStore()
    }

    private func syncDefaultJobSiteFromStore() {
        isSyncingDefaultSiteFromStore = true
        let resolved = JobSiteStore.defaultSiteId ?? configuredJobSites.first?.id
        if defaultJobSiteId != resolved {
            defaultJobSiteId = resolved
        }
        isSyncingDefaultSiteFromStore = false
    }

    private func resolvedSyncStatusMessage() -> String? {
        if let restore = syncQueue?.lastRestoreMessage, !restore.isEmpty {
            return restore
        }
        guard let error = syncQueue?.lastError, !error.isEmpty else { return nil }
        if isOnline && NetworkError.isOfflineMessage(error) {
            return nil
        }
        return error
    }

    private func reloadFaceScanPoseSettings() {
        isApplyingFaceScanBatch = true
        faceScanCenterEnabled = FaceScanSettings.isStepEnabled(.closeUp)
        faceScanLeftEnabled = FaceScanSettings.isStepEnabled(.lookLeft)
        faceScanRightEnabled = FaceScanSettings.isStepEnabled(.lookRight)
        faceScanUpEnabled = FaceScanSettings.isStepEnabled(.lookUp)
        faceScanDownEnabled = FaceScanSettings.isStepEnabled(.lookDown)
        faceScanLevel = FaceScanSettings.matchingLevel()
        isApplyingFaceScanBatch = false
    }

    func selectFaceScanLevel(_ level: FaceScanSettings.Level) async {
        isSavingFaceScanSettings = true
        defer { isSavingFaceScanSettings = false }
        isApplyingFaceScanBatch = true
        FaceScanSettings.applyLevel(level)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(180))
        reloadFaceScanPoseSettings()
        faceScanSettingsMessage = nil
    }

    private func saveFaceScanStep(_ step: FaceScanSettings.Step, enabled: Bool) async {
        guard !isApplyingFaceScanBatch else { return }
        guard FaceScanSettings.isStepEnabled(step) != enabled else { return }
        isSavingFaceScanSettings = true
        defer { isSavingFaceScanSettings = false }
        FaceScanSettings.setStepEnabled(step, enabled)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(180))
        faceScanLevel = FaceScanSettings.matchingLevel()
        faceScanSettingsMessage = nil
    }

    func testAPIConnection() async {
        isTestingAPI = true
        apiTestMessage = "Testing connection…"
        defer { isTestingAPI = false }

        let result = await APITestRunner.run(
            baseURL: apiBaseURL,
            username: adminUsername,
            password: adminPassword
        )
        apiTestResult = result
        apiTestMessage = result.summary
        showAPITestAlert = true
    }

    func signInAdmin() async {
        await APIService.shared.updateBaseURL(apiBaseURL)
        do {
            try await AdminSession.shared.signIn(username: adminUsername, password: adminPassword)
            adminPassword = ""
            refresh()
            statusMessage = "Signed in to IMS. Sync and restore are enabled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func signOutAdmin() {
        AdminSession.shared.signOut()
        refresh()
        statusMessage = "Admin signed out."
    }

    func restoreFromServer() async {
        guard AdminSession.shared.isAuthenticated else {
            statusMessage = "Sign in as admin before restoring."
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            refresh()
        }
        do {
            let summary = try await syncQueue?.restoreFromServer()
            if let summary {
                statusMessage = "Restore complete: \(summary.successMessage) This device works offline again."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Wipes local roster/DTR/enrollment data, then downloads everything from IMS (IMS unchanged).
    func testRestoreFromCloud() async {
        guard AdminSession.shared.isAuthenticated else {
            restoreTestMessage = "Sign in as sync admin first."
            showRestoreTestAlert = true
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            restoreTestMessage = NetworkError.offlineMessage
            showRestoreTestAlert = true
            return
        }
        isTestingRestore = true
        isSyncing = true
        defer {
            isTestingRestore = false
            isSyncing = false
            refresh()
        }
        do {
            await APIService.shared.updateBaseURL(apiBaseURL)
            await AdminSession.shared.restorePersistedSession()
            guard let result = try await syncQueue?.testRestoreFromServer() else {
                restoreTestMessage = "Sync is not ready yet. Try again."
                showRestoreTestAlert = true
                return
            }
            restoreTestMessage = result.report
            statusMessage = "Restore test OK: \(result.restored.successMessage)"
            showRestoreTestAlert = true
        } catch {
            restoreTestMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            showRestoreTestAlert = true
        }
    }

    func saveSupervisorPIN() {
        guard newSupervisorPIN == confirmSupervisorPIN else {
            statusMessage = "PIN confirmation does not match."
            return
        }
        guard SupervisorPINSettings.setPIN(newSupervisorPIN) else {
            statusMessage = "PIN must be 4–12 digits."
            return
        }
        newSupervisorPIN = ""
        confirmSupervisorPIN = ""
        supervisorPINEnabled = true
        statusMessage = "Supervisor PIN saved. Required before each punch."
    }

    func clearSupervisorPIN() {
        SupervisorPINSettings.clearPIN()
        supervisorPINEnabled = false
        newSupervisorPIN = ""
        confirmSupervisorPIN = ""
        statusMessage = "Supervisor PIN cleared."
    }
}
