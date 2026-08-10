//
//  MoreView.swift
//  ConsTrakr
//

import SwiftUI

struct MoreView: View {
    @Environment(AppAccessSession.self) private var access
    @State private var showAdminUnlock = false
    @AppStorage(AppConstants.UserDefaultsKeys.adminScannerTabEnabled) private var adminScannerTabEnabled = true

    var body: some View {
        NavigationStack {
            List {
                accessSection

                if access.canManageJobSites() {
                    NavigationLink {
                        JobSitesListView()
                    } label: {
                        Label("Job Sites", systemImage: "mappin.and.ellipse")
                    }
                }

                NavigationLink {
                    SettingsAppearanceView()
                } label: {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }

                NavigationLink {
                    SettingsSyncAccountView()
                } label: {
                    Label("Sync Account", systemImage: "person.badge.key.fill")
                }

                if access.canAccessAdminSettings() {
                    NavigationLink {
                        SettingsView(embedsNavigation: false)
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showAdminUnlock) {
                AdminUnlockSheet()
            }
        }
    }

    private var accessSection: some View {
        Section {
            if let siteTitle = access.operatorSiteTitle {
                LabeledContent("Your site") {
                    Text(siteTitle)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Text("No default job site is set. Unlock admin to configure job sites.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if access.isAdminUnlocked {
                LabeledContent("Admin mode") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Unlocked")
                            .foregroundStyle(.green)
                        if let name = access.unlockedOperatorName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: $adminScannerTabEnabled.withToggleBusy()) {
                    Text("Scanner tab")
                }
                Button("Lock admin") {
                    access.lock()
                }
            } else {
                Button {
                    showAdminUnlock = true
                } label: {
                    Label("Unlock admin", systemImage: "lock.open.fill")
                }
            }
        } footer: {
            if access.isAdminUnlocked {
                Text("Turn off Scanner tab if you are monitoring only. Operators always see the scanner after you lock admin.")
            } else {
                Text("Operators can register and edit employees for the site shown above. Unlock admin to manage job sites, settings, and delete employees.")
            }
        }
    }
}
