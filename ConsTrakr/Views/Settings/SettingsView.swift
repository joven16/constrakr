//
//  SettingsView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsView: View {
    @Environment(SyncQueue.self) private var syncQueue
    @AppStorage(AppConstants.UserDefaultsKeys.appTheme) private var appThemeRaw = AppTheme.system.rawValue
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
        Form {
            appearanceSection
            statusSection
            syncSection
            syncAccountSection
            configurationSection
            aboutSection
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
            if viewModel.isAdminAuthenticated {
                await viewModel.syncNowFull()
            } else {
                viewModel.refresh()
            }
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

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appThemeRaw) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your iPhone light or dark mode. Light and dark override it for this app only.")
        }
    }

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
            Toggle("Auto sync", isOn: $viewModel.autoSyncEnabled)
            if viewModel.autoSyncEnabled {
                Stepper(value: $viewModel.syncIntervalMinutes, in: SyncSettings.minIntervalMinutes...SyncSettings.maxIntervalMinutes) {
                    Text("Every \(viewModel.syncIntervalMinutes) min")
                }
            }
            Toggle("Photos & ID on Wi‑Fi only", isOn: $viewModel.uploadLargeFilesOnWiFiOnly)
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
                Text("Pull down here or on Employees / DTR to sync. Auto sync and Full sync run everything. Sign in below first.")
            }
        }
    }

    private var syncAccountSection: some View {
        Section {
            if viewModel.isAdminAuthenticated {
                LabeledContent("Signed in as", value: AdminSession.shared.username ?? "Admin")
                Button("Sign out", role: .destructive) {
                    viewModel.signOutAdmin()
                }
            } else {
                TextField("Admin username", text: $viewModel.adminUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.adminPassword)
                Button("Sign in") {
                    Task { await viewModel.signInAdmin() }
                }
                .disabled(viewModel.adminUsername.isEmpty || viewModel.adminPassword.isEmpty)
            }
        } header: {
            Text("Sync Account")
        } footer: {
            Text("Use your sync_admin credentials. Required for sync, restore, and cloud backup.")
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
                SettingsJobSiteView(viewModel: viewModel)
            } label: {
                settingsRow(
                    title: "Job sites & GPS",
                    subtitle: viewModel.siteGeofenceEnabled ? "Geofence on" : "Geofence off",
                    systemImage: "mappin.and.ellipse"
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Credits")
                    .font(.subheadline.weight(.semibold))
                Text("by Joven Lusterio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
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
