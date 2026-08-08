//
//  SettingsJobSiteView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsJobSiteView: View {
    @Bindable var viewModel: SettingsViewModel

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
                        set: { viewModel.setDefaultJobSiteId($0) }
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
                }
            } header: {
                Text("Default Job Site")
            } footer: {
                Text("Each employee’s assigned site is checked again when they punch Time In / Out.")
            }
        }
        .navigationTitle("Job Sites & GPS")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
            viewModel.reloadJobSiteSettings()
        }
    }
}
