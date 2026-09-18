//
//  SettingsDeviceTrackingView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsDeviceTrackingView: View {
    @State private var enabled = DeviceTrackingConfig.isEnabled
    @State private var normalInterval = DeviceTrackingConfig.normalIntervalMinutes
    @State private var activeInterval = DeviceTrackingConfig.activeIntervalMinutes
    @State private var signedIn = AdminSession.shared.isAuthenticated

    var body: some View {
        Form {
            if !signedIn {
                Section {
                    Text("Sign in under More → Sync Account before tracking or play-sound commands can work.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Device tracking", isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        DeviceTrackingConfig.isEnabled = value
                    }
            } footer: {
                Text("Disabled by default. Sends battery, network, and one-shot GPS (≤100 m accuracy) to the server.")
            }

            if enabled {
                Section("Intervals (minimum 15 min)") {
                    Stepper(value: $normalInterval, in: DeviceTrackingConfig.minIntervalMinutes...120) {
                        Text("Normal: every \(normalInterval) min")
                    }
                    .onChange(of: normalInterval) { _, value in
                        DeviceTrackingConfig.normalIntervalMinutes = value
                    }

                    Stepper(value: $activeInterval, in: DeviceTrackingConfig.minIntervalMinutes...120) {
                        Text("While charging: every \(activeInterval) min")
                    }
                    .onChange(of: activeInterval) { _, value in
                        DeviceTrackingConfig.activeIntervalMinutes = value
                    }
                }
            }

            Section {
                NavigationLink {
                    DeviceTrackingDiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
            }
        }
        .navigationTitle("Device tracking")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            enabled = DeviceTrackingConfig.isEnabled
            normalInterval = DeviceTrackingConfig.normalIntervalMinutes
            activeInterval = DeviceTrackingConfig.activeIntervalMinutes
            signedIn = AdminSession.shared.isAuthenticated
        }
    }
}
