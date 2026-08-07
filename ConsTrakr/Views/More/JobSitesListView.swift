//
//  JobSitesListView.swift
//  ConsTrakr
//

import SwiftUI

struct JobSitesListView: View {
    @State private var sites: [JobSite] = JobSiteStore.allSites
    @State private var showAddSite = false

    var body: some View {
        List {
            if sites.isEmpty {
                ContentUnavailableView {
                    Label("No Job Sites", systemImage: "mappin.and.ellipse")
                } description: {
                    Text("Add sites with a name, location label, and map pin. Employees are assigned to a site during registration.")
                }
            } else {
                ForEach(sites) { site in
                    NavigationLink {
                        JobSiteEditorView(existingSite: site)
                    } label: {
                        JobSiteRow(site: site, isDefault: site.id == JobSiteStore.defaultSiteId)
                    }
                }
                .onDelete(perform: deleteSites)
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
                JobSiteEditorView(existingSite: nil)
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        sites = JobSiteStore.allSites
    }

    private func deleteSites(at offsets: IndexSet) {
        for index in offsets {
            JobSiteStore.delete(id: sites[index].id)
        }
        reload()
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
        }
        .padding(.vertical, 2)
    }
}
