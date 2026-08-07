//
//  JobSiteMapPinEditor.swift
//  ConsTrakr
//

import MapKit
import SwiftUI

enum JobSiteMapLayer: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "square.3.layers.3d"
        }
    }

    var style: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic)
        case .satellite:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        }
    }
}

/// Map with a fixed center pin — pan/zoom moves the coordinate under the pin.
struct JobSiteMapPinEditor: View {
    @Binding var latitude: Double
    @Binding var longitude: Double
    var radiusMeters: Double
    /// Increment to recenter on the pin without changing zoom (GPS / manual coordinates).
    var recenterToken: Int = 0

    @State private var position: MapCameraPosition = .automatic
    @State private var cameraDistance: CLLocationDistance = 800
    @State private var didSeedCoordinate = false
    @State private var ignoreBindingRecenter = false
    @State private var mapLayer: JobSiteMapLayer = .standard

    private let minZoomDistance: CLLocationDistance = 80
    private let maxZoomDistance: CLLocationDistance = 5_000

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if hasPin {
                    MapCircle(center: pinCenter, radius: radiusMeters)
                        .foregroundStyle(Color.teal.opacity(0.18))
                        .stroke(Color.teal.opacity(0.85), lineWidth: 2)
                }
            }
            .mapStyle(mapLayer.style)
            .onMapCameraChange(frequency: .onEnd) { context in
                ignoreBindingRecenter = true
                latitude = context.region.center.latitude
                longitude = context.region.center.longitude
                cameraDistance = context.camera.distance
                didSeedCoordinate = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    ignoreBindingRecenter = false
                }
            }

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .offset(y: -18)
                .allowsHitTesting(false)

            Menu {
                Picker("Map layer", selection: $mapLayer) {
                    ForEach(JobSiteMapLayer.allCases) { layer in
                        Label(layer.label, systemImage: layer.systemImage)
                            .tag(layer)
                    }
                }
            } label: {
                Image(systemName: mapLayer.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Map layer")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(10)

            VStack(spacing: 8) {
                mapControlButton(systemName: "plus", accessibilityLabel: "Zoom in") {
                    adjustZoom(factor: 0.72)
                }
                mapControlButton(systemName: "minus", accessibilityLabel: "Zoom out") {
                    adjustZoom(factor: 1 / 0.72)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            seedInitialCamera()
        }
        .onChange(of: recenterToken) { _, _ in
            guard recenterToken > 0 else { return }
            recenterOnPin()
        }
    }

    private var hasPin: Bool {
        latitude != 0 || longitude != 0
    }

    private var pinCenter: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func mapControlButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func seedInitialCamera() {
        guard hasPin else {
            if !didSeedCoordinate {
                position = .userLocation(fallback: .automatic)
            }
            return
        }
        applyCamera(center: pinCenter, distance: cameraDistance)
        didSeedCoordinate = true
    }

    private func recenterOnPin() {
        guard hasPin else { return }
        applyCamera(center: pinCenter, distance: cameraDistance)
        didSeedCoordinate = true
    }

    private func adjustZoom(factor: Double) {
        guard hasPin else { return }
        let next = min(maxZoomDistance, max(minZoomDistance, cameraDistance * factor))
        cameraDistance = next
        applyCamera(center: pinCenter, distance: next)
    }

    private func applyCamera(center: CLLocationCoordinate2D, distance: CLLocationDistance) {
        position = .camera(
            MapCamera(
                centerCoordinate: center,
                distance: distance,
                heading: 0,
                pitch: 0
            )
        )
    }
}
