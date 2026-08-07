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
        case wrongJobSite(assignedSiteName: String, detectedSiteName: String?)
        case assignedSiteUnavailable(siteName: String)

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
                return "Outside \(siteName) (\(d)m away; allowed \(r)m). This punch is invalid."
            case .wrongJobSite(let assigned, let detected):
                if let detected, !detected.isEmpty {
                    return "Wrong job site — assigned to \(assigned) but you are at \(detected). This punch is invalid."
                }
                return "Wrong job site — you must be at \(assigned) to punch. This punch is invalid."
            case .assignedSiteUnavailable(let siteName):
                return "\(siteName) has no map pin on this device. Set coordinates in Job Sites, then try again."
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

        let location = try await authorizedLocation()
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

    /// Validates GPS for a specific employee — assigned site only; never falls back to the app default site.
    func verifyAttendanceSite(for employee: Employee) async throws {
        let assignedLabel = JobSiteStore.assignedSiteLabel(
            for: employee.assignedSiteId,
            fallbackName: employee.assignedSiteName
        )

        if let assignedId = employee.assignedSiteId {
            if let operatingId = JobSiteStore.currentOperatingSiteId(), operatingId != assignedId {
                throw GateError.wrongJobSite(
                    assignedSiteName: assignedLabel,
                    detectedSiteName: JobSiteStore.assignedSiteLabel(for: operatingId)
                )
            }

            guard let catalogSite = JobSiteStore.site(id: assignedId) else {
                throw GateError.wrongJobSite(assignedSiteName: assignedLabel, detectedSiteName: nil)
            }
            guard catalogSite.hasCoordinate else {
                throw GateError.assignedSiteUnavailable(siteName: catalogSite.displayTitle)
            }

            let location = try await authorizedLocation()

            if let detected = JobSiteStore.siteContaining(location: location), detected.id != assignedId {
                throw GateError.wrongJobSite(
                    assignedSiteName: catalogSite.displayTitle,
                    detectedSiteName: detected.displayTitle
                )
            }

            let siteLocation = CLLocation(latitude: catalogSite.latitude, longitude: catalogSite.longitude)
            let distance = location.distance(from: siteLocation)
            if distance > catalogSite.radiusMeters {
                throw GateError.outsideSite(
                    siteName: catalogSite.displayTitle,
                    distanceMeters: distance,
                    radiusMeters: catalogSite.radiusMeters
                )
            }
            return
        }

        guard SiteGeofenceSettings.isRequired, let defaultSite = JobSiteStore.defaultSite else {
            return
        }
        try await verifyInside(site: defaultSite)
    }

    /// Returns whether the device is inside the site, without throwing for outside range.
    func isInside(site: JobSite) async -> Result<Bool, GateError> {
        do {
            try await verifyInside(site: site)
            return .success(true)
        } catch let error as GateError {
            switch error {
            case .outsideSite, .wrongJobSite, .assignedSiteUnavailable:
                return .success(false)
            default:
                return .failure(error)
            }
        } catch {
            return .failure(.locationUnavailable)
        }
    }

    private func authorizedLocation() async throws -> CLLocation {
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

        return try await requestLocation(timeoutSeconds: 8)
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
