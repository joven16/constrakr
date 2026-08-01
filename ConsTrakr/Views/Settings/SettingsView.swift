//
//  SettingsView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsView: View {
    @Environment(SyncQueue.self) private var syncQueue
    @State private var viewModel = SettingsViewModel()
    var embedsNavigation: Bool = true

    var body: some View {
        Group {
            if embedsNavigation {
                NavigationStack { settingsForm }
            } else {
                settingsForm
            }
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(viewModel.isOnline ? "Online" : "Offline")
                        .foregroundStyle(viewModel.isOnline ? .green : .secondary)
                }
                LabeledContent("Pending Uploads", value: "\(viewModel.pendingCount)")
                if let last = viewModel.lastSyncDate {
                    LabeledContent("Last Sync", value: last.attendanceDisplay)
                }
                Button {
                    Task { await viewModel.syncNow() }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView()
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(viewModel.isSyncing)
            } header: {
                Text("Sync")
            } footer: {
                if let status = viewModel.statusMessage {
                    Text(status)
                } else {
                    Text("Offline-first: roster, encrypted face templates, enrollment photos, depth data, and attendance upload when online.")
                }
            }

            Section {
                if viewModel.isAdminAuthenticated {
                    LabeledContent("Admin", value: AdminSession.shared.username ?? "Signed in")
                    Button("Restore from Cloud Backup") {
                        Task { await viewModel.restoreFromServer() }
                    }
                    .disabled(viewModel.isSyncing || !viewModel.isOnline)
                    Button("Sign Out Admin", role: .destructive) {
                        viewModel.signOutAdmin()
                    }
                } else {
                    TextField("Admin username", text: $viewModel.adminUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.adminPassword)
                    Button("Sign In to Restore") {
                        Task { await viewModel.signInAdmin() }
                    }
                    .disabled(viewModel.adminUsername.isEmpty || viewModel.adminPassword.isEmpty)
                }
            } header: {
                Text("Device Restore")
            } footer: {
                Text("If this device is replaced, sign in and restore roster, face data, and attendance from your server. Face scanning works offline after restore.")
            }

            Section("API") {
                TextField("Base URL (HTTPS)", text: $viewModel.apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("Auto Sync", isOn: $viewModel.autoSyncEnabled)
            }

            Section {
                LabeledContent("Engine", value: MatchThresholdSettings.engineName)
                LabeledContent("Anti-Spoof") {
                    Text(CoreMLAntiSpoof.shared.isReady ? "MiniFASNetV2 (Core ML)" : "Heuristics only")
                        .foregroundStyle(CoreMLAntiSpoof.shared.isReady ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match Threshold: \(viewModel.matchThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(
                        value: $viewModel.matchThreshold,
                        in: viewModel.matchThresholdRange,
                        step: 0.01
                    )
                }
                Toggle("Keep debug camera frames", isOn: $viewModel.uploadRawFramesEnabled)
            } header: {
                Text("Face Recognition")
            } footer: {
                Text("Default AdaFace threshold is 0.45. Same person is often ~0.42–0.80. Lower the slider if valid faces show “Not recognized”; raise it to reduce lookalike matches. Re-register after switching engines — embeddings are incompatible.")
            }

            Section {
                Toggle("Require supervisor PIN", isOn: $viewModel.supervisorPINEnabled)
                SecureField("New PIN (4–12 digits)", text: $viewModel.newSupervisorPIN)
                    .keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $viewModel.confirmSupervisorPIN)
                    .keyboardType(.numberPad)
                Button("Save Supervisor PIN") {
                    viewModel.saveSupervisorPIN()
                }
                .disabled(viewModel.newSupervisorPIN.count < 4)
                if SupervisorPINSettings.hasPIN {
                    Button("Clear PIN", role: .destructive) {
                        viewModel.clearSupervisorPIN()
                    }
                }
            } header: {
                Text("Buddy-punch control")
            } footer: {
                Text("When enabled, Time In / Time Out asks for a supervisor PIN before the camera scan starts.")
            }

            Section {
                Toggle("Require on-site GPS", isOn: $viewModel.siteGeofenceEnabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Site radius: \(Int(viewModel.siteRadiusMeters)) m")
                    Slider(value: $viewModel.siteRadiusMeters, in: 50...500, step: 10)
                }
                Button {
                    Task { await viewModel.useCurrentLocationAsSite() }
                } label: {
                    if viewModel.isCapturingSiteLocation {
                        ProgressView()
                    } else {
                        Label("Use Current Location as Job Site", systemImage: "location.fill")
                    }
                }
                .disabled(viewModel.isCapturingSiteLocation)
                if SiteGeofenceSettings.hasSiteCoordinate {
                    LabeledContent(
                        "Site",
                        value: String(
                            format: "%.4f, %.4f",
                            SiteGeofenceSettings.latitude,
                            SiteGeofenceSettings.longitude
                        )
                    )
                    Button("Clear Job Site", role: .destructive) {
                        viewModel.clearSiteLocation()
                    }
                }
            } header: {
                Text("Job site geofence")
            } footer: {
                Text("Stand at the site and tap Use Current Location. Punches outside the radius are blocked.")
            }

            Section("About") {
                LabeledContent("App", value: AppConstants.appName)
                LabeledContent("Mode", value: "Offline-first")
                LabeledContent("Vision", value: "Face landmarks + head pose")
                LabeledContent("Face Model", value: MatchThresholdSettings.engineName)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            viewModel.configure(syncQueue: syncQueue)
        }
        .onChange(of: syncQueue.pendingCount) { _, _ in
            viewModel.refresh()
        }
    }
}
