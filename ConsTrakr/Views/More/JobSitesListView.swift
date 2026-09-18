//
//  JobSitesListView.swift
//  ConsTrakr
//

import SwiftUI

struct JobSitesListView: View {
    @Environment(SyncQueue.self) private var syncQueue

    @State private var sites: [JobSite] = JobSiteStore.allSites
    @State private var showAddSite = false
    @State private var geofenceEnabled = SiteGeofenceSettings.isEnabled
    @State private var showAdminCodePrompt = false
    @State private var pendingAction: PendingAdminAction?
    @State private var adminGateError: String?

    private enum PendingAdminAction {
        case geofence(Bool)
        case delete([UUID])
    }

    private var pendingJobSiteSync: Int {
        JobSiteStore.pendingSyncCount
    }

    private var adminPromptTitle: String {
        switch pendingAction {
        case .geofence: return "Change GPS requirement"
        case .delete: return "Delete job site"
        case nil: return "Admin code required"
        }
    }

    private var adminPromptMessage: String {
        switch pendingAction {
        case .geofence(let enabled):
            return enabled
                ? "Enter the admin code to require on-site GPS before attendance scans."
                : "Enter the admin code to turn off on-site GPS for attendance scans."
        case .delete(let ids):
            return ids.count == 1
                ? "Enter the admin code to delete this job site."
                : "Enter the admin code to delete \(ids.count) job sites."
        case nil:
            return "Enter the admin code to continue."
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Require on-site GPS", isOn: Binding(
                    get: { geofenceEnabled },
                    set: { requestGeofenceChange(to: $0) }
                ).withToggleBusy())
            } footer: {
                if let adminGateError {
                    Text(adminGateError)
                        .foregroundStyle(.red)
                } else {
                    Text("When on, the scanner tab is blocked until the phone is at the default job site. Open a site below, turn on Default for attendance checks, then Save. Updating sites always requires the admin code.")
                }
            }

            if pendingJobSiteSync > 0 {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pendingJobSiteSync) job site change\(pendingJobSiteSync == 1 ? "" : "s") waiting to sync")
                                .font(.subheadline)
                            Text("Pull down to sync now, or they'll upload automatically when you're back online.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if sites.isEmpty {
                ContentUnavailableView {
                    Label("No Job Sites", systemImage: "mappin.and.ellipse")
                } description: {
                    Text("Add a site with a name, map pin, and radius. Then set it as the default for attendance checks.")
                }
            } else {
                Section {
                    ForEach(sites) { site in
                        NavigationLink {
                            JobSiteEditorView(existingSite: site)
                        } label: {
                            JobSiteRow(site: site, isDefault: site.id == JobSiteStore.defaultSiteId)
                        }
                    }
                    .onDelete(perform: requestDeleteSites)
                } header: {
                    Text("Sites")
                } footer: {
                    Text("Select a site to edit it. Set Default for attendance checks, then Save. Saving or deleting requires the admin code.")
                }
            }
        }
        .navigationTitle("Job Sites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSite = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSite) {
            NavigationStack {
                JobSiteEditorView(existingSite: nil, showsCancelButton: true)
            }
        }
        .onAppear { reload(reconcilePending: true) }
        .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: DeviceStore.deviceDidChangeNotification)) { _ in
            adminGateError = nil
        }
        .refreshable {
            await syncQueue.syncNow(mode: .quick, scope: .all)
            reload(reconcilePending: true)
        }
        .fullScreenCover(isPresented: $showAdminCodePrompt) {
            AdminCodePromptSheet(
                title: adminPromptTitle,
                message: adminPromptMessage,
                onConfirm: { code in
                    try await AdminCodeService.verify(passcode: code)
                    switch pendingAction {
                    case .geofence(let enabled):
                        applyGeofenceChange(enabled: enabled)
                    case .delete(let ids):
                        for id in ids {
                            JobSiteStore.delete(id: id)
                        }
                        reload()
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

    private func reload(reconcilePending: Bool = false) {
        if reconcilePending {
            JobSiteStore.reconcilePendingSync()
        }
        sites = JobSiteStore.allSites
        geofenceEnabled = SiteGeofenceSettings.isEnabled
    }

    private func requestDeleteSites(at offsets: IndexSet) {
        adminGateError = nil
        let ids = offsets.map { sites[$0].id }
        do {
            try AdminCodeService.ensureChangeAllowed()
            pendingAction = .delete(ids)
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }

    private func requestGeofenceChange(to enabled: Bool) {
        guard enabled != geofenceEnabled else { return }
        adminGateError = nil

        if enabled && !JobSiteStore.hasConfiguredSites {
            geofenceEnabled = false
            adminGateError = "Add a job site first, then set one as the default for attendance checks."
            return
        }

        do {
            try AdminCodeService.ensureChangeAllowed()
            pendingAction = .geofence(enabled)
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }

    private func applyGeofenceChange(enabled: Bool) {
        SiteGeofenceSettings.isEnabled = enabled
        geofenceEnabled = enabled
    }
}

private struct JobSiteRow: View {
    let site: JobSite
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(site.displayTitle)
                    .font(.headline)
                if isDefault {
                    Text("Default")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.teal.opacity(0.15), in: Capsule())
                        .foregroundStyle(.teal)
                }
            }
            Text(site.displaySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isDefault {
                Text("Used for attendance GPS checks")
                    .font(.caption)
                    .foregroundStyle(.teal)
            }
        }
        .padding(.vertical, 2)
    }
}
