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
                if viewModel.isSyncing {
                    LabeledContent("Sync") {
                        ProgressView()
                    }
                }
                Toggle("Auto Sync", isOn: $viewModel.autoSyncEnabled)
                if viewModel.autoSyncEnabled {
                    Stepper(value: $viewModel.syncIntervalMinutes, in: SyncSettings.minIntervalMinutes...SyncSettings.maxIntervalMinutes) {
                        Text("Every \(viewModel.syncIntervalMinutes) min")
                    }
                }
            } header: {
                Text("Sync")
            } footer: {
                if let status = viewModel.statusMessage {
                    Text(status)
                } else if viewModel.autoSyncEnabled {
                    Text("Manual sync is on the Employees tab. Auto sync runs every \(SyncSettings.intervalLabel) while the app is open and on iOS background refresh (same interval; iOS may defer when battery is low). Sign in to IMS first.")
                } else {
                    Text("Auto sync is off. Sync manually from the Employees tab. Sign in to IMS first.")
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
                    Button("Sign In for Sync & Restore") {
                        Task { await viewModel.signInAdmin() }
                    }
                    .disabled(viewModel.adminUsername.isEmpty || viewModel.adminPassword.isEmpty)
                }
            } header: {
                Text("IMS Sync & Restore")
            } footer: {
                Text("Sign in with your IMS sync admin (e.g. sync_admin). Required for sync on the Employees tab and cloud restore to a replacement device. Restore downloads employees, face templates, enrollment photos, attendance history, and punch photos from the last 2 years.")
            }

            Section {
                TextField("Base URL (HTTPS)", text: $viewModel.apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Admin username", text: $viewModel.adminUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password (optional if signed in)", text: $viewModel.adminPassword)
                Button {
                    Task { await viewModel.testAPIConnection() }
                } label: {
                    if viewModel.isTestingAPI {
                        ProgressView()
                    } else {
                        Label("Test API Connection", systemImage: "network")
                    }
                }
                .disabled(viewModel.isTestingAPI)
            } header: {
                Text("IMS API")
            } footer: {
                if let apiTestMessage = viewModel.apiTestMessage {
                    Text(apiTestMessage)
                        .foregroundStyle(
                            viewModel.apiTestResult?.healthOK == true
                                && viewModel.apiTestResult?.loginOK == true
                                ? Color.green : Color.orange
                        )
                } else {
                    Text("If you already signed in above, leave password blank — Test API checks your saved session. To test a new password, enter it here.")
                }
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
                ForEach(FaceScanSettings.Level.allCases) { level in
                    Button {
                        viewModel.selectFaceScanLevel(level)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(level.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            if viewModel.faceScanLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if FaceScanSettings.isCustomConfiguration {
                    LabeledContent("Custom") {
                        Text("Manual angles below")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(FaceScanSettings.settingsLabel(for: .closeUp), isOn: $viewModel.faceScanCenterEnabled)
                Toggle(FaceScanSettings.settingsLabel(for: .lookLeft), isOn: $viewModel.faceScanLeftEnabled)
                Toggle(FaceScanSettings.settingsLabel(for: .lookRight), isOn: $viewModel.faceScanRightEnabled)
                Toggle(FaceScanSettings.settingsLabel(for: .lookUp), isOn: $viewModel.faceScanUpEnabled)
                Toggle(FaceScanSettings.settingsLabel(for: .lookDown), isOn: $viewModel.faceScanDownEnabled)
            } header: {
                Text("Face Scanner")
            } footer: {
                if let note = viewModel.faceScanSettingsMessage {
                    Text(note)
                        .foregroundStyle(.orange)
                } else {
                    Text("Controls the live checks during Time In / Time Out. Blink always runs first, then any enabled steps above, then 3D depth if available. Registration always captures all five angles.")
                }
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
        .onChange(of: syncQueue.lastError) { _, _ in
            viewModel.refresh()
        }
        .onChange(of: syncQueue.isSyncing) { _, _ in
            viewModel.refresh()
        }
        .onChange(of: syncQueue.lastSyncDate) { _, _ in
            viewModel.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppConstants.Notifications.networkConnectivityDidChange
            )
        ) { _ in
            viewModel.refresh()
        }
        .alert("API Connection Test", isPresented: $viewModel.showAPITestAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.apiTestMessage ?? "")
        }
    }
}
