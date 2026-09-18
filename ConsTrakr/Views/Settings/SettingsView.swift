//
//  SettingsView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsView: View {
    @Environment(SyncQueue.self) private var syncQueue
    @State private var viewModel = SettingsViewModel()
    @State private var showRestoreTestConfirmation = false
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
        List {
            if viewModel.canShowAdminSettingsSections {
                statusSection
                syncSection
                configurationSection
            }
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .task {
            await AdminSession.shared.restorePersistedSession()
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
        .onChange(of: syncQueue.syncProgressMessage) { _, _ in
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
        .refreshable {
            await viewModel.syncNowQuick()
        }
        .alert("Test cloud restore?", isPresented: $showRestoreTestConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Local & Restore", role: .destructive) {
                Task { await viewModel.testRestoreFromCloud() }
            }
        } message: {
            Text("This removes all employees, face enrollment, and DTR records from this device only, then downloads the full backup from the server. Your cloud data stays safe.")
        }
        .alert("Restore Test Result", isPresented: $viewModel.showRestoreTestAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.restoreTestMessage ?? "")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Network") {
                Text(viewModel.isOnline ? "Online" : "Offline")
                    .foregroundStyle(viewModel.isOnline ? .green : .secondary)
            }
            if viewModel.pendingCount > 0 {
                LabeledContent("Pending uploads", value: "\(viewModel.pendingCount)")
            }
            if let last = viewModel.lastSyncDate {
                LabeledContent("Last sync", value: last.attendanceDisplay)
            }
            if viewModel.isSyncing, let progress = viewModel.syncProgressMessage {
                LabeledContent("Progress") {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Status")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Auto sync", isOn: $viewModel.autoSyncEnabled.withToggleBusy())
            if viewModel.autoSyncEnabled {
                Stepper(value: $viewModel.syncIntervalMinutes, in: SyncSettings.minIntervalMinutes...SyncSettings.maxIntervalMinutes) {
                    Text("Every \(viewModel.syncIntervalMinutes) min")
                }
            }
            Toggle("Photos & ID on Wi‑Fi only", isOn: $viewModel.uploadLargeFilesOnWiFiOnly.withToggleBusy())
            if viewModel.isAdminAuthenticated {
                Button("Full sync now") {
                    Task { await viewModel.syncNowFull() }
                }
                .disabled(viewModel.isSyncing || !viewModel.isOnline)
            }
        } header: {
            Text("Sync")
        } footer: {
            if let status = viewModel.statusMessage {
                Text(status)
            } else {
                Text("Pull down here or on Employees / DTR to sync. Auto sync and Full sync run everything. Sign in under More → Sync Account first.")
            }
        }
    }

    private var configurationSection: some View {
        Section {
            NavigationLink {
                SettingsScannerView(viewModel: viewModel)
            } label: {
                settingsRow(
                    title: "Scanner & face match",
                    subtitle: "Threshold and liveness steps",
                    systemImage: "faceid"
                )
            }

            NavigationLink {
                SettingsSupervisorPINView(viewModel: viewModel)
            } label: {
                settingsRow(
                    title: "Supervisor PIN",
                    subtitle: SupervisorPINSettings.isRequired ? "Required before punch" : "Off",
                    systemImage: "lock.shield"
                )
            }

            NavigationLink {
                SettingsDeviceTrackingView()
            } label: {
                settingsRow(
                    title: "Device tracking",
                    subtitle: DeviceTrackingConfig.isEnabled ? "On" : "Off",
                    systemImage: "location.circle"
                )
            }

            NavigationLink {
                SettingsAdvancedView(
                    viewModel: viewModel,
                    showRestoreTestConfirmation: $showRestoreTestConfirmation
                )
            } label: {
                settingsRow(
                    title: "Advanced",
                    subtitle: "Server URL, restore, diagnostics",
                    systemImage: "wrench.and.screwdriver"
                )
            }
        } header: {
            Text("Configuration")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: AppConstants.appName)
            LabeledContent("Face model", value: MatchThresholdSettings.engineName)
            LabeledContent("Owner/Developer", value: "Joven Lusterio")
        }
    }

    private func settingsRow(title: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.teal)
        }
    }
}
