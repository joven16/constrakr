//
//  SettingsJobSiteView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsJobSiteView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var showAdminCodePrompt = false
    @State private var pendingDefaultSiteId: UUID?
    @State private var adminGateError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Require on-site GPS", isOn: $viewModel.siteGeofenceEnabled)
            } footer: {
                Text("When on, the scanner tab is blocked until the phone is at the default job site.")
            }

            Section {
                if viewModel.configuredJobSites.isEmpty {
                    NavigationLink {
                        JobSitesListView()
                    } label: {
                        Label("Add Job Sites", systemImage: "plus.circle")
                    }
                } else {
                    Picker("Default site", selection: Binding(
                        get: { viewModel.effectiveDefaultSiteId },
                        set: { newId in
                            requestDefaultSiteChange(to: newId)
                        }
                    )) {
                        ForEach(viewModel.configuredJobSites) { site in
                            Text(site.displayTitle).tag(Optional(site.id))
                        }
                    }
                    NavigationLink {
                        JobSitesListView()
                    } label: {
                        Label("Manage Job Sites", systemImage: "mappin.and.ellipse")
                    }
                    if let site = JobSiteStore.defaultSite {
                        LabeledContent("Radius", value: "\(Int(site.radiusMeters.rounded())) m")
                        LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", site.latitude, site.longitude))
                    }
                    if let operatorName = DeviceStore.assignedUserName ?? DeviceStore.assignedUserUsername {
                        LabeledContent("Device operator", value: operatorName)
                    }
                }
            } header: {
                Text("Default Job Site")
            } footer: {
                Text("Changing the default site requires the admin code of the user assigned to this device in IMS.")
            }

            if let adminGateError {
                Section {
                    Text(adminGateError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Job Sites & GPS")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
            viewModel.reloadJobSiteSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: DeviceStore.deviceDidChangeNotification)) { _ in
            adminGateError = nil
        }
        .sheet(isPresented: $showAdminCodePrompt) {
            AdminCodePromptSheet(
                title: "Change default site",
                message: "Enter the admin code to change which job site this device uses for attendance and DTR.",
                confirmLabel: "Confirm",
                onConfirm: { code in
                    try await AdminCodeService.verify(passcode: code)
                    if let pendingDefaultSiteId {
                        viewModel.applyDefaultJobSiteChange(to: pendingDefaultSiteId)
                    }
                    showAdminCodePrompt = false
                    self.pendingDefaultSiteId = nil
                    adminGateError = nil
                },
                onCancel: {
                    pendingDefaultSiteId = nil
                    showAdminCodePrompt = false
                }
            )
        }
    }

    private func requestDefaultSiteChange(to newId: UUID?) {
        guard newId != viewModel.effectiveDefaultSiteId else { return }
        adminGateError = nil
        do {
            try AdminCodeService.ensureChangeAllowed()
            pendingDefaultSiteId = newId
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }
}
