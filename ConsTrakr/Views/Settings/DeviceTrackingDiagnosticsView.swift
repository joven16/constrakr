//
//  DeviceTrackingDiagnosticsView.swift
//  ConsTrakr
//

import SwiftUI

struct DeviceTrackingDiagnosticsView: View {
    @State private var pendingCount = 0
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var signedIn = AdminSession.shared.isAuthenticated

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Sync account", value: signedIn ? "Signed in" : "Not signed in")
                LabeledContent("Tracking", value: DeviceTrackingConfig.isEnabled ? "On" : "Off")
                LabeledContent("Network", value: NetworkMonitor.shared.isConnected ? "Online" : "Offline")
                LabeledContent("Pending queue", value: "\(pendingCount)")
            }

            Section("Last activity") {
                LabeledContent("Last collect", value: formatMillis(DeviceTrackingMetadata.lastCollectMillis))
                LabeledContent("Last sync", value: formatMillis(DeviceTrackingMetadata.lastSuccessfulSyncMillis))
                LabeledContent("Last GPS", value: formatMillis(DeviceTrackingMetadata.lastLocationMillis))
                if let lat = DeviceTrackingMetadata.lastLocationLat,
                   let lng = DeviceTrackingMetadata.lastLocationLng {
                    LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", lat, lng))
                }
                if let accuracy = DeviceTrackingMetadata.lastLocationAccuracy {
                    LabeledContent("GPS accuracy", value: String(format: "%.1f m", accuracy))
                }
            }

            if let trackingError = DeviceTrackingCoordinator.lastErrorMessage {
                Section("Last tracking error") {
                    Text(trackingError).foregroundStyle(.red)
                }
            }

            if let commandError = DeviceCommandService.shared.lastErrorMessage {
                Section("Last play-sound error") {
                    Text(commandError).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await collectAndSync() }
                } label: {
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text("Collecting…")
                        }
                    } else {
                        Label("Collect & sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isWorking)

                Button {
                    Task { await pollPlaySound() }
                } label: {
                    Label("Check play-sound command", systemImage: "speaker.wave.2.fill")
                }
            }
        }
        .navigationTitle("Tracking diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPending() }
        .onAppear {
            signedIn = AdminSession.shared.isAuthenticated
        }
    }

    private func refreshPending() async {
        pendingCount = DeviceHeartbeatStore.pendingCount()
    }

    private func collectAndSync() async {
        isWorking = true
        defer { isWorking = false }
        statusMessage = await DeviceTrackingCoordinator.collectAndSyncIfDue(force: true)
        await refreshPending()
    }

    private func pollPlaySound() async {
        await DeviceCommandService.shared.pollRemoteCommands()
        statusMessage = DeviceCommandService.shared.lastErrorMessage ?? "Polled server for play-sound command."
    }

    private func formatMillis(_ millis: Int64) -> String {
        guard millis > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
