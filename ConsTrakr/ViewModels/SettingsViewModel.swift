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
            if siteGeofenceEnabled && !SiteGeofenceSettings.hasSiteCoordinate {
                siteGeofenceEnabled = false
                statusMessage = "Set the job site location first."
                return
            }
            SiteGeofenceSettings.isEnabled = siteGeofenceEnabled
        }
    }

    var siteRadiusMeters: Double {
        didSet {
            SiteGeofenceSettings.radiusMeters = siteRadiusMeters
        }
    }

    private(set) var isCapturingSiteLocation = false

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
        supervisorPINEnabled = SupervisorPINSettings.isRequired
        siteGeofenceEnabled = SiteGeofenceSettings.isRequired
        siteRadiusMeters = SiteGeofenceSettings.radiusMeters
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

    func useCurrentLocationAsSite() async {
        isCapturingSiteLocation = true
        defer { isCapturingSiteLocation = false }
        do {
            let location = try await Self.requestOneShotLocation()
            SiteGeofenceSettings.setSite(
                coordinate: location.coordinate,
                radiusMeters: siteRadiusMeters
            )
            siteGeofenceEnabled = true
            statusMessage = String(
                format: "Job site set (%.5f, %.5f) · ±%.0fm",
                location.coordinate.latitude,
                location.coordinate.longitude,
                siteRadiusMeters
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearSiteLocation() {
        SiteGeofenceSettings.clearSite()
        siteGeofenceEnabled = false
        statusMessage = "Job site geofence cleared."
    }

    private static func requestOneShotLocation() async throws -> CLLocation {
        final class OneShot: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
            let manager = CLLocationManager()
            var continuation: CheckedContinuation<CLLocation, Error>?

            func capture() async throws -> CLLocation {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                    manager.delegate = self
                    manager.desiredAccuracy = kCLLocationAccuracyBest
                    manager.requestLocation()
                }
            }

            func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
                guard let location = locations.last else { return }
                continuation?.resume(returning: location)
                continuation = nil
            }

            func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }

        let shooter = OneShot()
        let status = shooter.manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways || status == .notDetermined else {
            throw SiteLocationGate.GateError.permissionDenied
        }
        if status == .notDetermined {
            shooter.manager.requestWhenInUseAuthorization()
            try await Task.sleep(for: .milliseconds(600))
        }
        return try await shooter.capture()
    }
}
