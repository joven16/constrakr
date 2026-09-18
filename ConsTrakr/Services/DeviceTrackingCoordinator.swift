//
//  DeviceTrackingCoordinator.swift
//  ConsTrakr
//

import Foundation

@MainActor
enum DeviceTrackingCoordinator {
    private static var trackingTimer: Timer?
    private static var commandTimer: Timer?

    static var lastErrorMessage: String?

    static func start() {
        startCommandPolling()
        restartTrackingTimer()
        Task {
            await DeviceCommandService.shared.pollRemoteCommands()
            await collectAndSyncIfDue(force: false)
        }
    }

    static func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        commandTimer?.invalidate()
        commandTimer = nil
    }

    static func restart() {
        stop()
        start()
    }

    private static func startCommandPolling() {
        commandTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                await DeviceCommandService.shared.pollRemoteCommands()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        commandTimer = timer
    }

    private static func restartTrackingTimer() {
        trackingTimer?.invalidate()
        guard DeviceTrackingConfig.isEnabled else {
            trackingTimer = nil
            return
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                _ = await collectAndSyncIfDue(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    static func collectAndSyncIfDue(force: Bool = false) async -> String? {
        guard DeviceTrackingConfig.isEnabled else {
            return "Turn on Device tracking in Settings first."
        }
        guard AdminSession.shared.isAuthenticated else {
            return "Sign in under More → Sync Account first."
        }
        guard await APIService.shared.hasAuthToken() else {
            return "Missing auth token — sign in again."
        }

        do {
            try await ensureDeviceRegistered()
        } catch {
            lastErrorMessage = error.localizedDescription
            return "Device registration failed: \(error.localizedDescription)"
        }

        let snapshot = await DeviceTrackingCollector.collectSnapshot()
        let now = snapshot.payload.timestamp
        DeviceTrackingMetadata.lastCollectMillis = now
        if snapshot.hadLocation {
            DeviceTrackingMetadata.lastLocationMillis = now
            DeviceTrackingMetadata.lastLocationLat = snapshot.payload.latitude
            DeviceTrackingMetadata.lastLocationLng = snapshot.payload.longitude
            DeviceTrackingMetadata.lastLocationAccuracy = snapshot.payload.accuracyMeters
        }

        if !force, shouldSkipDuplicate(now: now, charging: snapshot.payload.isCharging) {
            let synced = await syncPending()
            return synced > 0 ? "Synced \(synced) pending heartbeat(s)" : "Skipped — interval not reached yet."
        }

        _ = DeviceHeartbeatStore.enqueue(snapshot.payload)
        let synced = await syncPending()
        if synced > 0 {
            lastErrorMessage = nil
            return "Synced \(synced) heartbeat(s)"
        }
        if let lastErrorMessage {
            return "Queued locally — upload failed: \(lastErrorMessage)"
        }
        return "Queued locally — waiting for network."
    }

    static func syncPending() async -> Int {
        guard AdminSession.shared.isAuthenticated else { return 0 }
        guard await APIService.shared.hasAuthToken() else { return 0 }

        do {
            try await ensureDeviceRegistered()
        } catch {
            lastErrorMessage = error.localizedDescription
            return 0
        }

        var synced = 0
        for row in DeviceHeartbeatStore.pending() {
            do {
                let device = try await APIService.shared.postDeviceHeartbeat(row.apiBody())
                DeviceHeartbeatStore.markSynced(id: row.id)
                DeviceTrackingMetadata.lastSuccessfulSyncMillis = Int64(Date().timeIntervalSince1970 * 1000)
                DeviceStore.update(from: device)
                await DeviceCommandService.shared.handle(device: device)
                synced += 1
                lastErrorMessage = nil
            } catch NetworkError.unauthorized {
                lastErrorMessage = "Server sign-in expired."
                AdminSession.shared.handleUnauthorized()
                break
            } catch let error as NetworkError {
                lastErrorMessage = error.localizedDescription
                break
            } catch {
                lastErrorMessage = error.localizedDescription
                break
            }
        }
        return synced
    }

    private static func ensureDeviceRegistered() async throws {
        let device = try await APIService.shared.registerDevice(
            localId: DeviceStore.localId,
            name: DeviceStore.syncName,
            appVersion: DeviceStore.appVersion
        )
        DeviceStore.update(from: device)
    }

    private static func shouldSkipDuplicate(now: Int64, charging: Bool) -> Bool {
        guard let latest = DeviceHeartbeatStore.latest() else { return false }
        let gap = Int64(DeviceTrackingConfig.intervalMillis(charging: charging))
        return now - latest.timestamp < gap
    }
}
