//
//  SettingsAdvancedView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsAdvancedView: View {
    @Bindable var viewModel: SettingsViewModel
    @Binding var showRestoreTestConfirmation: Bool

    var body: some View {
        Form {
            Section {
                TextField("Base URL (HTTPS)", text: $viewModel.apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
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
                Text("IMS Server")
            } footer: {
                if let apiTestMessage = viewModel.apiTestMessage {
                    Text(apiTestMessage)
                        .foregroundStyle(
                            viewModel.apiTestResult?.healthOK == true
                                && viewModel.apiTestResult?.loginOK == true
                                ? Color.green : Color.orange
                        )
                } else {
                    Text("Host only — the app adds /constrakr-api automatically. Test checks health and your saved admin session.")
                }
            }

            if viewModel.isAdminAuthenticated {
                Section {
                    Button("Restore from Cloud Backup") {
                        Task { await viewModel.restoreFromServer() }
                    }
                    .disabled(viewModel.isSyncing || !viewModel.isOnline)

                    Button {
                        showRestoreTestConfirmation = true
                    } label: {
                        if viewModel.isTestingRestore {
                            HStack {
                                ProgressView()
                                Text("Testing restore…")
                            }
                        } else {
                            Label("Test Restore (Clear Local & Download)", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isSyncing || viewModel.isTestingRestore || !viewModel.isOnline)
                } header: {
                    Text("Device Recovery")
                } footer: {
                    Text("Restore adds IMS data to this device. Test Restore wipes local employees, face data, and DTR first — simulates a replacement phone. IMS cloud data is not deleted.")
                }
            }

            Section("Diagnostics") {
                LabeledContent("Mode", value: "Offline-first")
                LabeledContent("Vision", value: "Face landmarks + head pose")
                Toggle("Keep debug camera frames", isOn: $viewModel.uploadRawFramesEnabled)
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .alert("API Connection Test", isPresented: $viewModel.showAPITestAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.apiTestMessage ?? "")
        }
    }
}
