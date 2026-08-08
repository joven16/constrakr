//
//  ClockIntegrityGuard.swift
//  ConsTrakr
//
//  Detects manual device clock changes and compares against server time when online.
//

import Foundation

enum ClockIntegrityError: LocalizedError {
    case deviceClockDrift(driftSeconds: TimeInterval)
    case clockManipulationDetected
    case serverTimeUnavailable

    var errorDescription: String? {
        switch self {
        case .deviceClockDrift(let driftSeconds):
            let minutes = Int((driftSeconds / 60).rounded())
            return "Device date/time looks wrong (about \(minutes) min off). Turn on Settings → General → Date & Time → Set Automatically, then try again."
        case .clockManipulationDetected:
            return "Device date/time was changed. Restore automatic date & time in Settings, then try again."
        case .serverTimeUnavailable:
            return "Could not verify device time with the server. Check your connection or try again."
        }
    }
}

@MainActor
final class ClockIntegrityGuard {
    static let shared = ClockIntegrityGuard()

    private struct Checkpoint: Codable {
        var wallTime: TimeInterval
        var uptime: TimeInterval
    }

    private var cachedServerTime: Date?
    private var cachedServerTimeFetchedAt: Date?

    private init() {}

    /// Refreshes the offline jump baseline whenever the scanner opens.
    func bootstrapIfNeeded() {
        recordCheckpoint()
    }

    /// Call before recording attendance. Prefers server time when online.
    func verifyBeforePunch() async throws {
        if NetworkMonitor.shared.isConnected {
            do {
                try await verifyOnlineDrift()
                // Server agrees with device — iOS may have auto-corrected since the last checkpoint.
                recordCheckpoint()
                return
            } catch let error as ClockIntegrityError {
                if case .deviceClockDrift = error {
                    throw error
                }
            } catch {
                // Unreachable server or missing server_time — fall back to offline jump check.
            }
        }
        try verifyNoClockJump()
    }

    /// Best timestamp for a new punch — server-adjusted when online, device time offline.
    func preferredPunchTimestamp() -> Date {
        if let serverTime = cachedServerTime, let fetchedAt = cachedServerTimeFetchedAt {
            let elapsed = Date().timeIntervalSince(fetchedAt)
            return serverTime.addingTimeInterval(elapsed)
        }
        return Date()
    }

    func recordSuccessfulPunch() {
        recordCheckpoint()
        cachedServerTime = nil
        cachedServerTimeFetchedAt = nil
    }

    func verifyNoClockJump() throws {
        guard let last = loadCheckpoint() else {
            recordCheckpoint()
            return
        }

        let nowWall = Date().timeIntervalSince1970
        let nowUptime = ProcessInfo.processInfo.systemUptime

        if nowUptime < last.uptime {
            recordCheckpoint()
            return
        }

        let wallDelta = nowWall - last.wallTime
        if wallDelta > AppConstants.clockCheckpointMaxAgeSeconds {
            recordCheckpoint()
            return
        }

        let uptimeDelta = nowUptime - last.uptime
        let drift = abs(wallDelta - uptimeDelta)

        if drift > AppConstants.maxClockJumpToleranceSeconds {
            throw ClockIntegrityError.clockManipulationDetected
        }
    }

    private func verifyOnlineDrift() async throws {
        let serverTime: Date
        do {
            serverTime = try await APIService.shared.fetchServerTime()
        } catch {
            throw ClockIntegrityError.serverTimeUnavailable
        }

        cachedServerTime = serverTime
        cachedServerTimeFetchedAt = Date()

        let drift = abs(serverTime.timeIntervalSince(Date()))
        if drift > AppConstants.maxClockDriftSeconds {
            throw ClockIntegrityError.deviceClockDrift(driftSeconds: drift)
        }
    }

    private func recordCheckpoint() {
        let checkpoint = Checkpoint(
            wallTime: Date().timeIntervalSince1970,
            uptime: ProcessInfo.processInfo.systemUptime
        )
        if let data = try? JSONEncoder().encode(checkpoint) {
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.clockIntegrityCheckpoint)
        }
    }

    private func loadCheckpoint() -> Checkpoint? {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.clockIntegrityCheckpoint) else {
            return nil
        }
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }
}
