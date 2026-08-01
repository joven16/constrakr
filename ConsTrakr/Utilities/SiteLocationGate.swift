//
//  SiteLocationGate.swift
//  ConsTrakr
//
// One-shot location check against the configured job-site geofence.
//

import CoreLocation
import Foundation

@MainActor
final class SiteLocationGate: NSObject, CLLocationManagerDelegate {
    enum GateError: LocalizedError {
        case permissionDenied
        case locationUnavailable
        case timedOut
        case outsideSite(distanceMeters: Double, radiusMeters: Double)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Location access is required for on-site attendance. Enable it in Settings."
            case .locationUnavailable:
                return "Could not read GPS. Move outdoors or wait for a signal, then try again."
            case .timedOut:
                return "GPS timed out. Try again outdoors, or turn off site geofence in Settings."
            case .outsideSite(let distance, let radius):
                let d = Int(distance.rounded())
                let r = Int(radius.rounded())
                return "Outside job site (\(d)m away; allowed \(r)m). Buddy punches off-site are blocked."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// No-op when geofence is disabled; throws when outside / unavailable / timed out.
    func verifyInsideSiteIfRequired() async throws {
        guard SiteGeofenceSettings.isRequired,
              let site = SiteGeofenceSettings.siteCoordinate
        else { return }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait for the user to answer the system prompt.
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(250))
                let auth = manager.authorizationStatus
                if auth != .notDetermined { break }
            }
        }

        let auth = manager.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            throw GateError.permissionDenied
        }

        let location = try await requestLocation(timeoutSeconds: 8)
        let siteLocation = CLLocation(latitude: site.latitude, longitude: site.longitude)
        let distance = location.distance(from: siteLocation)
        let radius = SiteGeofenceSettings.radiusMeters
        if distance > radius {
            throw GateError.outsideSite(distanceMeters: distance, radiusMeters: radius)
        }
    }

    private func requestLocation(timeoutSeconds: Double) async throws -> CLLocation {
        try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { @MainActor in
                try await self.requestLocationOnce()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw GateError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func requestLocationOnce() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            // Cancel any prior waiter so we never double-resume.
            if let prior = self.continuation {
                prior.resume(throwing: GateError.locationUnavailable)
                self.continuation = nil
            }
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: GateError.locationUnavailable)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Authorization wait loop in verifyInsideSiteIfRequired polls status.
    }
}
