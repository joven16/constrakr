//
//  MainTabView.swift
//  ConsTrakr
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppTabRouter.self) private var tabRouter
    @Environment(AppAccessSession.self) private var access
    @Environment(SyncQueue.self) private var syncQueue

    private var showsScannerTab: Bool {
        !access.isAdminUnlocked || ScannerTabSettings.isEnabledForAdmin
    }

    var body: some View {
        @Bindable var tabRouter = tabRouter

        TabView(selection: $tabRouter.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .badge(syncQueue.pendingCount > 0 ? syncQueue.pendingCount : 0)
                .tag(AppTabRouter.Tab.dashboard)

            EmployeeListView()
                .tabItem {
                    Label("Employees", systemImage: "person.3.fill")
                }
                .tag(AppTabRouter.Tab.employees)

            if showsScannerTab {
                AttendanceScannerView()
                    .tabItem {
                        Label("Scanner", systemImage: "camera.viewfinder")
                    }
                    .tag(AppTabRouter.Tab.scanner)
            }

            DTRView()
                .tabItem {
                    Label("Time Record", systemImage: "calendar")
                }
                .tag(AppTabRouter.Tab.dtr)

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(AppTabRouter.Tab.more)
        }
        .tint(.cyan)
        .simultaneousGesture(tabSwipeGesture)
        .onAppear {
            leaveScannerTabIfHidden()
        }
        .onChange(of: showsScannerTab) { _, _ in
            leaveScannerTabIfHidden()
        }
        .onChange(of: access.isAdminUnlocked) { _, _ in
            leaveScannerTabIfHidden()
        }
        .onReceive(NotificationCenter.default.publisher(for: ScannerTabSettings.didChangeNotification)) { _ in
            leaveScannerTabIfHidden()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppAccessSession.sessionDidChangeNotification)) { _ in
            leaveScannerTabIfHidden()
        }
    }

    private func leaveScannerTabIfHidden() {
        if !showsScannerTab, tabRouter.selectedTab == .scanner {
            tabRouter.selectedTab = .dashboard
        }
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 80 else { return }
                if horizontal < 0 {
                    tabRouter.selectNextTab(showsScanner: showsScannerTab)
                } else {
                    tabRouter.selectPreviousTab(showsScanner: showsScannerTab)
                }
            }
    }
}
