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
                    Text("Offline-first: employees, encrypted embeddings, and attendance upload when online.")
                }
            }

            Section {
                if viewModel.isAdminAuthenticated {
                    LabeledContent("Admin", value: AdminSession.shared.username ?? "Signed in")
                    Button("Restore Employees & Embeddings") {
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
                Text("After restore, face recognition continues fully offline. INTEGRATION: wire admin login to your backend.")
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
                Text("AdaFace cosine similarity is typically ~0.40–0.80 for the same person. Delete old employees and re-register after switching to AdaFace — previous embeddings are incompatible. Raise the threshold to reduce false matches.")
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
