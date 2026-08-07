//
//  JobSite.swift
//  ConsTrakr
//

import CoreLocation
import Foundation

struct JobSite: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    /// Human-readable place label (e.g. "Makati HQ", "Site B – Pasig").
    var locationLabel: String
    var latitude: Double
    var longitude: Double
    /// Allowed punch radius from the pinned coordinate.
    var radiusMeters: Double

    init(
        id: UUID = UUID(),
        name: String,
        locationLabel: String = "",
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150
    ) {
        self.id = id
        self.name = name
        self.locationLabel = locationLabel
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = max(50, radiusMeters)
    }

    var hasCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed site" : trimmed
    }

    var displaySubtitle: String {
        let place = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if place.isEmpty {
            return String(format: "%.4f, %.4f · ±%.0f m", latitude, longitude, radiusMeters)
        }
        return "\(place) · ±\(Int(radiusMeters.rounded())) m"
    }
}
