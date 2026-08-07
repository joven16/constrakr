//
//  SiteLocationGate.swift
//  ConsTrakr
//
// One-shot location check against a job-site geofence.
//

import CoreLocation
import Foundation

@MainActor
final class SiteLocationGate: NSObject, CLLocationManagerDelegate {
    enum GateError: LocalizedError {
        case permissionDenied
        case locationUnavailable
        case timedOut
        case outsideSite(siteName: String, distanceMeters: Double, radiusMeters: Double)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Location access is required for on-site attendance. Enable GPS in iPhone Settings → ConsTrakr → Location."
            case .locationUnavailable:
                return "Could not read GPS. Move outdoors or wait for a signal, then try again."
            case .timedOut:
                return "GPS timed out. Try again outdoors, or turn off site geofence in Settings."
            case .outsideSite(let siteName, let distance, let radius):
                let d = Int(distance.rounded())
                let r = Int(radius.rounded())
                return "Outside \(siteName) (\(d)m away; allowed \(r)m). Move to the site or update location in Settings → Job Sites."
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
              let site = JobSiteStore.defaultSite
        else { return }
        try await verifyInside(site: site)
    }

    func verifyInside(site: JobSite) async throws {
        guard site.hasCoordinate else { return }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
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
        if distance > site.radiusMeters {
            throw GateError.outsideSite(
                siteName: site.displayTitle,
                distanceMeters: distance,
                radiusMeters: site.radiusMeters
            )
        }
    }

    /// Returns whether the device is inside the site, without throwing for outside range.
    func isInside(site: JobSite) async -> Result<Bool, GateError> {
        do {
            try await verifyInside(site: site)
            return .success(true)
        } catch let error as GateError {
            switch error {
            case .outsideSite:
                return .success(false)
            default:
                return .failure(error)
            }
        } catch {
            return .failure(.locationUnavailable)
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
