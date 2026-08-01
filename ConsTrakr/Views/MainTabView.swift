//
//  MainTabView.swift
//  ConsTrakr
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppTabRouter.self) private var tabRouter

    var body: some View {
        @Bindable var tabRouter = tabRouter

        TabView(selection: $tabRouter.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(AppTabRouter.Tab.dashboard)

            EmployeeListView()
                .tabItem {
                    Label("Employees", systemImage: "person.3.fill")
                }
                .tag(AppTabRouter.Tab.employees)

            AttendanceScannerView()
                .tabItem {
                    Label("Scanner", systemImage: "camera.viewfinder")
                }
                .tag(AppTabRouter.Tab.scanner)

            DTRView()
                .tabItem {
                    Label("DTR", systemImage: "calendar")
                }
                .tag(AppTabRouter.Tab.dtr)

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(AppTabRouter.Tab.more)
        }
        .tint(.cyan)
    }
}
