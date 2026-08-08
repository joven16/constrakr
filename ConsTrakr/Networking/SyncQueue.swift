//
//  SyncQueue.swift
//  ConsTrakr
//
//  CHANGE: Still the observable sync status used by the existing UI, but push work
//  now goes through SyncService (employees → embeddings → attendance).
//

import Foundation
import SwiftData

@MainActor
@Observable
final class SyncQueue {
    private(set) var isSyncing = false
    /// Last time a sync pass completed successfully (data reached IMS or nothing pending).
    private(set) var lastSyncDate: Date?
    /// Last time a sync was attempted (success or failure).
    private(set) var lastSyncAttemptDate: Date?
    private(set) var lastError: String?
    private(set) var pendingCount = 0
    private(set) var lastRestoreMessage: String?
    private(set) var lastPushSummary: SyncService.PushSyncSummary?
    private(set) var lastEmployeeSyncReport: EmployeeSyncReport?
    private(set) var syncProgressMessage: String?

    private let syncService: SyncService
    private var context: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var historyClearObserver: NSObjectProtocol?
    private var networkObserver: NSObjectProtocol?

    init(api: APIService = .shared) {
        self.syncService = SyncService(api: api)
        self.syncService.attach(queue: self)
    }

    var service: SyncService { syncService }

    func configure(context: ModelContext) {
        self.context = context
        syncService.configure(context: context)
        refreshPendingCount()

        if historyClearObserver == nil {
            historyClearObserver = NotificationCenter.default.addObserver(
                forName: AppConstants.Notifications.attendanceHistoryDidClear,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPendingCount()
                }
            }
        }

        if networkObserver == nil {
            networkObserver = NotificationCenter.default.addObserver(
                forName: AppConstants.Notifications.networkConnectivityDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleNetworkConnectivityChange()
                }
            }
        }

        if NetworkMonitor.shared.isConnected {
            clearStaleOfflineError()
        }
    }

    private func handleNetworkConnectivityChange() {
        if NetworkMonitor.shared.isConnected {
            clearStaleOfflineError()
        }
    }

    private func clearStaleOfflineError() {
        if NetworkError.isOfflineMessage(lastError) {
            lastError = nil
        }
    }

    func startAutoSync() {
        syncTask?.cancel()
        BackgroundSyncScheduler.scheduleNextSync()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncIfNeeded()
                try? await Task.sleep(for: .seconds(SyncSettings.intervalSeconds))
            }
        }
    }

    func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
    }

    func syncIfNeeded() async {
        let autoSync = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled) as? Bool ?? true
        guard autoSync else { return }
        guard NetworkMonitor.shared.isConnected else {
            lastError = NetworkError.offline.localizedDescription
            return
        }
        clearStaleOfflineError()
        await syncNow(mode: .full, scope: .all)
    }

    func syncNow(mode: SyncMode = .full, scope: SyncScope = .all, dtrFocusDate: Date? = nil) async {
        guard !isSyncing, let context else { return }

        lastSyncAttemptDate = Date()
        syncProgressMessage = syncProgressLabel(mode: mode, scope: scope)
        await AdminSession.shared.restorePersistedSession()

        if await APIService.shared.isUsingPlaceholderHost() {
            lastError = "Set your real server URL in Settings (not your-server.example.com)."
            return
        }

        if SyncAuthStore.isTokenExpired() {
            AdminSession.shared.handleUnauthorized()
            lastError = "Server sign-in expired. Open Settings → Sync account and sign in again."
            return
        }

        guard AdminSession.shared.isAuthenticated else {
            lastError = "Sign in under Settings → Sync account before syncing."
            return
        }
        guard await APIService.shared.hasAuthToken() else {
            lastError = "Sign in under Settings → Sync account before syncing."
            AdminSession.shared.handleUnauthorized()
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            syncProgressMessage = nil
            refreshPendingCount()
        }

        do {
            let summary = try await syncService.performPushSync(
                context: context,
                mode: mode,
                scope: scope,
                dtrFocusDate: dtrFocusDate
            )
            lastPushSummary = summary
            lastEmployeeSyncReport = summary.employeeSyncReport
            lastSyncDate = Date()
            if summary.employeesStillLocalOnly > 0 || summary.hasChildUploadIssues || summary.employeesUploadFailed > 0 {
                lastError = summary.failureMessage
            } else {
                lastError = nil
            }
            BackgroundSyncScheduler.scheduleNextSync()
        } catch NetworkError.unauthorized {
            AdminSession.shared.handleUnauthorized()
            lastError = "Server sign-in expired or invalid. Sign in again under Settings."
        } catch NetworkError.offline {
            lastError = NetworkError.offline.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Admin restore entry point used by Settings.
    func restoreFromServer() async throws -> SyncService.RestoreSummary {
        guard let context else { throw NetworkError.invalidResponse }
        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            refreshPendingCount()
        }
        let summary = try await syncService.restoreFromServer(context: context)
        lastRestoreMessage = summary.successMessage
        lastSyncDate = Date()
        lastSyncAttemptDate = Date()
        return summary
    }

    /// Clears local data then runs a full cloud restore — for testing replacement-device recovery.
    func testRestoreFromServer() async throws -> RestoreTestResult {
        guard let context else { throw NetworkError.invalidResponse }
        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            refreshPendingCount()
        }
        let before = try RestoreTestService.snapshot(context: context)
        try RestoreTestService.wipeLocalData(context: context)
        let summary = try await syncService.restoreFromServer(context: context)
        lastRestoreMessage = summary.successMessage
        lastSyncDate = Date()
        lastSyncAttemptDate = Date()
        return RestoreTestResult(wiped: before, restored: summary)
    }

    func refreshPendingCount() {
        guard let context else { return }
        let attendance = AttendanceRepository(context: context)
        let employees = EmployeeRepository(context: context)
        let embeddings = FaceEmbeddingRepository(context: context)
        let photos = FaceEnrollmentPhotoRepository(context: context)
        let a = (try? attendance.pendingCount()) ?? 0
        let e = (try? employees.pendingCount()) ?? 0
        let f = (try? embeddings.pendingCount()) ?? 0
        let p = (try? photos.pendingCount()) ?? 0
        pendingCount = a + e + f + p
    }

    func updateSyncProgress(_ message: String?) {
        syncProgressMessage = message
    }

    private func syncProgressLabel(mode: SyncMode, scope: SyncScope) -> String {
        switch scope {
        case .attendance:
            return "Syncing DTR…"
        case .employees:
            return mode == .quick ? "Syncing employees…" : "Syncing…"
        case .all:
            return mode == .quick ? "Quick sync…" : "Syncing…"
        }
    }

    /// Compare local roster vs IMS without uploading.
    func checkEmployeesOnIMS() async throws -> EmployeeSyncReport {
        guard let context else { throw NetworkError.invalidResponse }
        await AdminSession.shared.restorePersistedSession()
        return try await EmployeeSyncChecker.check(context: context, repair: true)
    }
}
