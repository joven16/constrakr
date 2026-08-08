//
//  SettingsJobSiteView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsJobSiteView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var showAdminCodePrompt = false
    @State private var pendingAction: AdminGatePendingAction?
    @State private var adminGateError: String?

    private enum AdminGatePendingAction {
        case defaultSite(UUID?)
        case geofence(Bool)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Require on-site GPS", isOn: Binding(
                    get: { viewModel.siteGeofenceEnabled },
                    set: { requestGeofenceChange(to: $0) }
                ))
            } footer: {
                Text("When on, the scanner tab is blocked until the phone is at the default job site. Turning this on or off requires a 6-digit admin code.")
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
                    if !DeviceStore.assignedUserLabels.isEmpty {
                        LabeledContent("Device operators") {
                            Text(DeviceStore.assignedUserLabels.joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            } header: {
                Text("Default Job Site")
            } footer: {
                Text("Changing the default site requires a 6-digit admin code from any user assigned to this device on the web dashboard.")
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
        .fullScreenCover(isPresented: $showAdminCodePrompt) {
            AdminCodePromptSheet(
                title: adminPromptTitle,
                message: adminPromptMessage,
                onConfirm: { code in
                    try await AdminCodeService.verify(passcode: code)
                    switch pendingAction {
                    case .defaultSite(let siteId):
                        viewModel.applyDefaultJobSiteChange(to: siteId)
                    case .geofence(let enabled):
                        viewModel.applyGeofenceChange(enabled: enabled)
                    case nil:
                        break
                    }
                    showAdminCodePrompt = false
                    pendingAction = nil
                    adminGateError = nil
                },
                onCancel: {
                    pendingAction = nil
                    showAdminCodePrompt = false
                }
            )
        }
    }

    private var adminPromptTitle: String {
        switch pendingAction {
        case .geofence:
            return "Change GPS requirement"
        case .defaultSite, nil:
            return "Change default site"
        }
    }

    private var adminPromptMessage: String {
        switch pendingAction {
        case .geofence(let enabled):
            if enabled {
                return "Enter the admin code to require on-site GPS before attendance scans."
            }
            return "Enter the admin code to turn off on-site GPS for attendance scans."
        case .defaultSite:
            return "Enter the admin code to change which job site this device uses for attendance and DTR."
        case nil:
            return "Enter the admin code to continue."
        }
    }

    private func requestDefaultSiteChange(to newId: UUID?) {
        guard newId != viewModel.effectiveDefaultSiteId else { return }
        adminGateError = nil
        do {
            try AdminCodeService.ensureChangeAllowed()
            pendingAction = .defaultSite(newId)
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }

    private func requestGeofenceChange(to enabled: Bool) {
        guard enabled != viewModel.siteGeofenceEnabled else { return }
        adminGateError = nil
        do {
            try AdminCodeService.ensureChangeAllowed()
            pendingAction = .geofence(enabled)
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }
}
