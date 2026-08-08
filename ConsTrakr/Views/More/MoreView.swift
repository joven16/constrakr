//
//  MoreView.swift
//  ConsTrakr
//

import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    JobSitesListView()
                } label: {
                    Label("Job Sites", systemImage: "mappin.and.ellipse")
                }

                NavigationLink {
                    SettingsView(embedsNavigation: false)
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
