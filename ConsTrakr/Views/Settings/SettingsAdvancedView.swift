//
//  SettingsAdvancedView.swift
//  ConsTrakr
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsAdvancedView: View {
    @Bindable var viewModel: SettingsViewModel
    @Binding var showRestoreTestConfirmation: Bool

    @State private var deviceNameText = ""
    @State private var didCopyDeviceID = false

    var body: some View {
        Form {
            deviceSection

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
                Text("Server URL")
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
                    Text("Restore adds server data to this device. Test Restore wipes local employees, face data, and DTR first — simulates a replacement phone. Cloud data on the server is not deleted.")
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
        .onAppear {
            deviceNameText = viewModel.reloadDeviceNameDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: DeviceStore.deviceDidChangeNotification)) { _ in
            deviceNameText = viewModel.reloadDeviceNameDraft()
        }
        .alert("API Connection Test", isPresented: $viewModel.showAPITestAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.apiTestMessage ?? "")
        }
    }

    private var deviceSection: some View {
        Section {
            TextField("Device name", text: $deviceNameText)
                .textInputAutocapitalization(.words)
                .onSubmit {
                    Task { await viewModel.saveDeviceName(deviceNameText) }
                }

            if viewModel.isSavingDeviceName {
                HStack {
                    ProgressView()
                    Text("Syncing device name…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("iPhone/iPad name", value: DeviceStore.systemDeviceName)

            VStack(alignment: .leading, spacing: 6) {
                Text("Device ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(DeviceStore.localId.uuidString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Button {
                copyDeviceID()
            } label: {
                Label(didCopyDeviceID ? "Copied" : "Copy device ID", systemImage: didCopyDeviceID ? "checkmark" : "doc.on.doc")
            }

            if DeviceStore.usesCustomName {
                Button("Use iPhone/iPad name") {
                    deviceNameText = DeviceStore.systemDeviceName
                    Task { await viewModel.resetDeviceNameToSystem() }
                }
            }
        } header: {
            Text("This device")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("This name appears on the web Devices list. Use a custom label like Gate 2 kiosk, or keep your iPhone/iPad name.")
                if let status = viewModel.deviceNameStatusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear {
            let trimmed = deviceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != DeviceStore.syncName else { return }
            Task { await viewModel.saveDeviceName(trimmed) }
        }
    }

    private func copyDeviceID() {
#if canImport(UIKit)
        UIPasteboard.general.string = DeviceStore.localId.uuidString
#endif
        didCopyDeviceID = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyDeviceID = false
        }
    }
}
