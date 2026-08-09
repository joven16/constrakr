//
//  ViewSiteFilterToolbar.swift
//  ConsTrakr
//

import SwiftUI

struct ViewSiteFilterToolbar: View {
    @Environment(AppAccessSession.self) private var access
    var onSiteChanged: () -> Void

    var body: some View {
        if access.isAdminUnlocked, !access.selectableSites.isEmpty {
            Menu {
                ForEach(access.selectableSites) { site in
                    Button {
                        access.setAdminViewSite(site.id)
                        onSiteChanged()
                    } label: {
                        if access.effectiveViewSiteId == site.id {
                            Label(site.displayTitle, systemImage: "checkmark")
                        } else {
                            Text(site.displayTitle)
                        }
                    }
                }
            } label: {
                Label {
                    Text(access.effectiveViewSiteTitle ?? "Site")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "building.2")
                }
                .font(.subheadline)
            }
            .accessibilityLabel("View site")
        }
    }
}
