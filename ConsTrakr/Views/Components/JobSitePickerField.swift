//
//  JobSitePickerField.swift
//  ConsTrakr
//

import SwiftUI

struct JobSitePickerField: View {
    @Binding var selectedSiteId: UUID?
    var allowNone: Bool = false

    private var sites: [JobSite] { JobSiteStore.allSites.filter(\.hasCoordinate) }

    var body: some View {
        Group {
            if sites.isEmpty {
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
                    LabeledContent("Radius", value: "\(Int(site.radiusMeters.rounded())) m")
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
    }
}
