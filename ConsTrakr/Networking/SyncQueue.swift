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
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?
    private(set) var pendingCount = 0
    private(set) var lastRestoreMessage: String?

    private let syncService: SyncService
    private var context: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var historyClearObserver: NSObjectProtocol?

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
                Task { @MainActor in
                    self?.refreshPendingCount()
                }
            }
        }
    }

    func startAutoSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncIfNeeded()
                try? await Task.sleep(for: .seconds(AppConstants.syncIntervalSeconds))
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
        await syncNow()
    }

    func syncNow() async {
        guard !isSyncing, let context else { return }
        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            refreshPendingCount()
        }

        do {
            // CHANGE: full offline-first push (not attendance-only).
            try await syncService.performPushSync(context: context)
            lastSyncDate = Date()
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
        lastRestoreMessage = "Restored \(summary.employees) employees, \(summary.embeddings) embeddings, \(summary.enrollmentPhotos) photos."
        lastSyncDate = Date()
        return summary
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
}
