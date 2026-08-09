//
//  JobSiteEditorView.swift
//  ConsTrakr
//

import CoreLocation
import SwiftUI

private struct JobSiteFormSnapshot: Equatable {
    var name: String
    var locationLabel: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var isDefaultSite: Bool

    static let empty = JobSiteFormSnapshot(
        name: "",
        locationLabel: "",
        latitude: 0,
        longitude: 0,
        radiusMeters: 100,
        isDefaultSite: false
    )

    static func from(site: JobSite) -> JobSiteFormSnapshot {
        JobSiteFormSnapshot(
            name: site.name.trimmingCharacters(in: .whitespacesAndNewlines),
            locationLabel: site.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: site.latitude,
            longitude: site.longitude,
            radiusMeters: JobSite.clampedRadius(site.radiusMeters),
            isDefaultSite: site.id == JobSiteStore.defaultSiteId
        )
    }

    func matchesCurrent(
        name: String,
        locationLabel: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        isDefaultSite: Bool
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName == self.name
            && trimmedLocation == self.locationLabel
            && coordinatesEqual(latitude, self.latitude)
            && coordinatesEqual(longitude, self.longitude)
            && radiusMeters == self.radiusMeters
            && isDefaultSite == self.isDefaultSite
    }

    private func coordinatesEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.000001
    }
}

struct JobSiteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppAccessSession.self) private var access

    let existingSite: JobSite?
    /// Shown when presented in a sheet (add flow) where swipe-to-dismiss isn't obvious.
    var showsCancelButton = false

    private let mapHeight: CGFloat = 300

    @State private var name = ""
    @State private var locationLabel = ""
    @State private var latitude: Double = 0
    @State private var longitude: Double = 0
    @State private var radiusMeters: Double = 100
    @State private var isDefaultSite = false
    @State private var isCapturingLocation = false
    @State private var mapRecenterToken = 0
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var isSyncingCoordinateFields = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showAdminCodePrompt = false
    @State private var pendingSite: JobSite?
    @State private var pendingSetDefault = false
    @State private var initialSnapshot = JobSiteFormSnapshot.empty

    private var isEditing: Bool { existingSite != nil }

    private var currentSnapshot: JobSiteFormSnapshot {
        JobSiteFormSnapshot(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            locationLabel: locationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            isDefaultSite: isDefaultSite
        )
    }

    private var formIsValid: Bool {
        !currentSnapshot.name.isEmpty
            && (currentSnapshot.latitude != 0 || currentSnapshot.longitude != 0)
    }

    private var hasChanges: Bool {
        !initialSnapshot.matchesCurrent(
            name: name,
            locationLabel: locationLabel,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            isDefaultSite: isDefaultSite
        )
    }

    private var canSave: Bool {
        formIsValid && hasChanges
    }

    var body: some View {
        Form {
            Section {
                TextField("Site name", text: $name)
                TextField("Location (e.g. Makati HQ)", text: $locationLabel)
            } header: {
                Text("Site details")
            }

            if isEditing {
                Section {
                    Toggle("Default site for attendance checks", isOn: $isDefaultSite)
                } footer: {
                    Text("The default site is used when an employee has no assigned site, and to gate the scanner tab.")
                }
            }

            Section {
                JobSiteMapPinEditor(
                    latitude: $latitude,
                    longitude: $longitude,
                    radiusMeters: radiusMeters,
                    recenterToken: mapRecenterToken
                )
                .frame(height: mapHeight)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Radius: \(Int(radiusMeters.rounded())) m")
                    Slider(value: $radiusMeters, in: JobSite.minRadiusMeters...JobSite.maxRadiusMeters, step: 5)
                }

                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    if isCapturingLocation {
                        ProgressView()
                    } else {
                        Label("Use My Current Location", systemImage: "location.fill")
                    }
                }
                .disabled(isCapturingLocation)
            } header: {
                Text("Map pin")
            } footer: {
                Text("Pan the map, use +/− to zoom, or tap the layer button for Standard, Satellite, or Hybrid view. The red pin marks the site center and the teal circle shows the attendance radius.")
            }

            Section {
                TextField("Latitude", text: $latitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { applyManualCoordinates() }

                TextField("Longitude", text: $longitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { applyManualCoordinates() }

                Button("Apply Coordinates") {
                    applyManualCoordinates()
                }
                .disabled(!canApplyManualCoordinates)
            } header: {
                Text("Manual coordinates")
            } footer: {
                Text("Enter latitude (-90 to 90) and longitude (-180 to 180), then apply to move the map pin.")
            }
        }
        .navigationTitle(isEditing ? "Edit Site" : "Add Site")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveSite() }
                    .disabled(!canSave)
            }
        }
        .task(id: existingSite?.id) {
            if let existingSite {
                loadExisting()
                initialSnapshot = JobSiteFormSnapshot.from(site: existingSite)
            } else {
                initialSnapshot = .empty
            }
        }
        .onChange(of: latitude) { _, _ in syncCoordinateFieldsFromState() }
        .onChange(of: longitude) { _, _ in syncCoordinateFieldsFromState() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(isPresented: $showAdminCodePrompt) {
            AdminCodePromptSheet(
                title: "Save job site",
                message: "Enter the admin code to save changes.",
                onConfirm: { code in
                    try await AdminCodeService.verify(passcode: code)
                    if let pendingSite {
                        commitSave(site: pendingSite, setDefault: pendingSetDefault)
                    }
                    showAdminCodePrompt = false
                    self.pendingSite = nil
                },
                onCancel: {
                    pendingSite = nil
                    showAdminCodePrompt = false
                }
            )
        }
    }

    private func loadExisting() {
        guard let existingSite else { return }
        name = existingSite.name
        locationLabel = existingSite.locationLabel
        latitude = existingSite.latitude
        longitude = existingSite.longitude
        radiusMeters = JobSite.clampedRadius(existingSite.radiusMeters)
        isDefaultSite = existingSite.id == JobSiteStore.defaultSiteId
        syncCoordinateFieldsFromState()
    }

    private var canApplyManualCoordinates: Bool {
        parsedManualCoordinates() != nil
    }

    private func parsedManualCoordinates() -> (latitude: Double, longitude: Double)? {
        let latText = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lonText = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lat = Double(latText), let lon = Double(lonText) else { return nil }
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    private func syncCoordinateFieldsFromState() {
        guard !isSyncingCoordinateFields else { return }
        isSyncingCoordinateFields = true
        defer { isSyncingCoordinateFields = false }
        guard latitude != 0 || longitude != 0 else {
            latitudeText = ""
            longitudeText = ""
            return
        }
        latitudeText = String(format: "%.6f", latitude)
        longitudeText = String(format: "%.6f", longitude)
    }

    private func applyManualCoordinates() {
        guard let coords = parsedManualCoordinates() else {
            errorMessage = "Enter valid latitude (-90 to 90) and longitude (-180 to 180)."
            return
        }
        latitude = coords.latitude
        longitude = coords.longitude
        mapRecenterToken += 1
    }

    private func saveSite() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Site name is required."
            return
        }
        guard latitude != 0 || longitude != 0 else {
            errorMessage = "Drop a pin on the map or use your current location."
            return
        }

        let site = JobSite(
            id: existingSite?.id ?? UUID(),
            name: trimmedName,
            locationLabel: locationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters
        )
        let setDefault: Bool
        if isEditing {
            setDefault = isDefaultSite
        } else {
            // New sites only become default when there isn't one yet.
            setDefault = JobSiteStore.defaultSiteId == nil
        }

        if isEditing {
            if access.isAdminUnlocked {
                commitSave(site: site, setDefault: setDefault)
                return
            }
            pendingSite = site
            pendingSetDefault = setDefault
            do {
                try AdminCodeService.ensureChangeAllowed()
                showAdminCodePrompt = true
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        commitSave(site: site, setDefault: setDefault)
    }

    private func commitSave(site: JobSite, setDefault: Bool) {
        JobSiteStore.upsert(site)
        if setDefault {
            JobSiteStore.setDefaultSite(id: site.id)
        }
        dismiss()
    }

    private func useCurrentLocation() async {
        isCapturingLocation = true
        defer { isCapturingLocation = false }
        do {
            let location = try await JobSiteLocationCapture.requestOneShot()
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            mapRecenterToken += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum JobSiteLocationCapture {
    @MainActor
    static func requestOneShot() async throws -> CLLocation {
        final class OneShot: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
            let manager = CLLocationManager()
            var continuation: CheckedContinuation<CLLocation, Error>?

            func capture() async throws -> CLLocation {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                    manager.delegate = self
                    manager.desiredAccuracy = kCLLocationAccuracyBest
                    let status = manager.authorizationStatus
                    if status == .notDetermined {
                        manager.requestWhenInUseAuthorization()
                    } else if status == .denied || status == .restricted {
                        continuation.resume(throwing: SiteLocationGate.GateError.permissionDenied)
                        self.continuation = nil
                        return
                    }
                    manager.requestLocation()
                }
            }

            func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
                guard let location = locations.last else { return }
                continuation?.resume(returning: location)
                continuation = nil
            }

            func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
                continuation?.resume(throwing: SiteLocationGate.GateError.locationUnavailable)
                continuation = nil
            }
        }
        return try await OneShot().capture()
    }
}
