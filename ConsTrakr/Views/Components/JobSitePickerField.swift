//
//  JobSitePickerField.swift
//  ConsTrakr
//

import SwiftUI

struct JobSitePickerField: View {
    @Binding var selectedSiteId: UUID?
    var allowNone: Bool = false
    var coordinateSitesOnly: Bool = true
    /// When set, the picker is read-only and fixed to this site (operator mode).
    var lockedSiteId: UUID? = nil

    private var sites: [JobSite] {
        let all = JobSiteStore.allSites
        return coordinateSitesOnly ? all.filter(\.hasCoordinate) : all
    }

    var body: some View {
        Group {
            if let lockedSiteId {
                lockedSiteContent(siteId: lockedSiteId)
            } else if sites.isEmpty {
                Text("No job sites yet — add one in More → Job Sites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Assigned site", selection: $selectedSiteId) {
                    if allowNone {
                        Text("None (use default)").tag(UUID?.none)
                    }
                    ForEach(sites) { site in
                        Text(site.displayTitle).tag(Optional(site.id))
                    }
                }
                .pickerStyle(.menu)

                if let site = JobSiteStore.site(id: selectedSiteId) {
                    LabeledContent("Location", value: site.locationLabel.isEmpty ? "—" : site.locationLabel)
                    if coordinateSitesOnly {
                        LabeledContent("Radius", value: "\(Int(site.radiusMeters.rounded())) m")
                    }
                    Text(site.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if allowNone, JobSiteStore.defaultSite != nil {
                    Text("Uses default site: \(JobSiteStore.defaultSite!.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if let lockedSiteId {
                selectedSiteId = lockedSiteId
            }
        }
        .onChange(of: lockedSiteId) { _, newValue in
            if let newValue {
                selectedSiteId = newValue
            }
        }
    }

    @ViewBuilder
    private func lockedSiteContent(siteId: UUID) -> some View {
        if let site = JobSiteStore.site(id: siteId) {
            LabeledContent("Assigned site", value: site.displayTitle)
            LabeledContent("Location", value: site.locationLabel.isEmpty ? "—" : site.locationLabel)
            if coordinateSitesOnly {
                LabeledContent("Radius", value: "\(Int(site.radiusMeters.rounded())) m")
            }
        } else {
            Text("Assigned site is not available on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
