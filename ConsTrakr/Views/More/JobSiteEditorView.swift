//
//  JobSiteEditorView.swift
//  ConsTrakr
//

import CoreLocation
import SwiftUI

struct JobSiteEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existingSite: JobSite?

    @State private var name = ""
    @State private var locationLabel = ""
    @State private var latitude: Double = 0
    @State private var longitude: Double = 0
    @State private var radiusMeters: Double = 150
    @State private var isDefaultSite = false
    @State private var isCapturingLocation = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var isEditing: Bool { existingSite != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (latitude != 0 || longitude != 0)
    }

    var body: some View {
        Form {
            Section {
                TextField("Site name", text: $name)
                TextField("Location (e.g. Makati HQ)", text: $locationLabel)
            } header: {
                Text("Site details")
            }

            Section {
                JobSiteMapPinEditor(latitude: $latitude, longitude: $longitude)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Radius: \(Int(radiusMeters.rounded())) m")
                    Slider(value: $radiusMeters, in: 50...500, step: 10)
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

                if latitude != 0 || longitude != 0 {
                    LabeledContent(
                        "Coordinates",
                        value: String(format: "%.5f, %.5f", latitude, longitude)
                    )
                }
            } header: {
                Text("Map pin")
            } footer: {
                Text("Pan and zoom the map — the red pin marks where Time In / Time Out must happen within the radius.")
            }

            if isEditing {
                Section {
                    Toggle("Default site for attendance checks", isOn: $isDefaultSite)
                } footer: {
                    Text("The default site is used when an employee has no assigned site, and to gate the scanner tab.")
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Site" : "Add Site")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveSite() }
                    .disabled(!canSave)
            }
        }
        .onAppear { loadExisting() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadExisting() {
        guard let existingSite else { return }
        name = existingSite.name
        locationLabel = existingSite.locationLabel
        latitude = existingSite.latitude
        longitude = existingSite.longitude
        radiusMeters = existingSite.radiusMeters
        isDefaultSite = existingSite.id == JobSiteStore.defaultSiteId
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
        JobSiteStore.upsert(site)
        if isDefaultSite || !isEditing || JobSiteStore.defaultSiteId == nil {
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
