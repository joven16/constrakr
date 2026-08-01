//
//  MainTabView.swift
//  ConsTrakr
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }

            EmployeeListView()
                .tabItem {
                    Label("Employees", systemImage: "person.3.fill")
                }

            AttendanceScannerView()
                .tabItem {
                    Label("Scanner", systemImage: "camera.viewfinder")
                }

            DTRView()
                .tabItem {
                    Label("DTR", systemImage: "calendar")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .tint(.cyan)
    }
}
