//
//  SettingsViewModel.swift
//  ConsTrakr
//
//  CHANGE: Admin sign-in + restore hooks for new-device offline bootstrap.
//

import Foundation
import SwiftData

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

    var adminUsername = ""
    var adminPassword = ""

    private(set) var pendingCount = 0
    private(set) var lastSyncDate: Date?
    private(set) var isSyncing = false
    private(set) var isOnline = false
    private(set) var isAdminAuthenticated = false
    private(set) var statusMessage: String?

    private var syncQueue: SyncQueue?

    init() {
        apiBaseURL = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiBaseURL)
            ?? AppConstants.apiBaseURL
        autoSyncEnabled = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled) as? Bool ?? true
        matchThreshold = Double(MatchThresholdSettings.current)
        uploadRawFramesEnabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.uploadRawFramesEnabled)
    }

    /// Slider range depends on whether AdaFace or the handcrafted fallback is active.
    var matchThresholdRange: ClosedRange<Double> {
        CoreMLFaceRecognizer.shared.isReady ? 0.30...0.70 : 0.80...0.99
    }

    func configure(syncQueue: SyncQueue) {
        self.syncQueue = syncQueue
        refresh()
    }

    func refresh() {
        pendingCount = syncQueue?.pendingCount ?? 0
        lastSyncDate = syncQueue?.lastSyncDate
        isSyncing = syncQueue?.isSyncing ?? false
        isOnline = NetworkMonitor.shared.isConnected
        isAdminAuthenticated = AdminSession.shared.isAuthenticated
        statusMessage = syncQueue?.lastError ?? syncQueue?.lastRestoreMessage
    }

    func syncNow() async {
        isSyncing = true
        await syncQueue?.syncNow()
        refresh()
        if syncQueue?.lastError == nil {
            statusMessage = "Sync completed (employees, embeddings, attendance)."
        }
    }

    func signInAdmin() async {
        do {
            try await AdminSession.shared.signIn(username: adminUsername, password: adminPassword)
            adminPassword = ""
            refresh()
            statusMessage = "Admin signed in. You can restore this device."
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
        defer { refresh() }
        do {
            let summary = try await syncQueue?.restoreFromServer()
            if let summary {
                statusMessage = "Restore complete: \(summary.employees) employees, \(summary.embeddings) embeddings, \(summary.attendance) attendance. Device works offline."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
