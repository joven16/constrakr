//
//  JobSiteMapPinEditor.swift
//  ConsTrakr
//

import MapKit
import SwiftUI

/// Map with a fixed center pin — pan/zoom moves the coordinate under the pin.
struct JobSiteMapPinEditor: View {
    @Binding var latitude: Double
    @Binding var longitude: Double

    @State private var position: MapCameraPosition = .automatic
    @State private var didSeedCoordinate = false

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: [.pan, .zoom]) {}
                .mapStyle(.standard(elevation: .realistic))
                .onMapCameraChange(frequency: .onEnd) { context in
                    latitude = context.region.center.latitude
                    longitude = context.region.center.longitude
                    didSeedCoordinate = true
                }

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .offset(y: -18)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            seedCameraIfNeeded()
        }
    }

    private func seedCameraIfNeeded() {
        let hasPin = latitude != 0 || longitude != 0
        if hasPin {
            position = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
            didSeedCoordinate = true
        } else if !didSeedCoordinate {
            position = .userLocation(fallback: .automatic)
        }
    }
}
