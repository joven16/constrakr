//
//  AppRootView.swift
//  ConsTrakr
//
//  Hosts lifecycle hooks for auto-sync (foreground timer + BGTask only).
//

import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer
    @Bindable var syncQueue: SyncQueue
    @Bindable var tabRouter: AppTabRouter

    var body: some View {
        MainTabView()
            .environment(syncQueue)
            .environment(tabRouter)
            .onAppear {
                let context = modelContainer.mainContext
                DataController.seedMockDataIfNeeded(context: context)
                try? EmployeeRepository(context: context).repairStaleSyncState()
                syncQueue.configure(context: context)
                BackgroundSyncScheduler.register(syncQueue: syncQueue)
                Task { await AdminSession.shared.restorePersistedSession() }
                let autoSync = UserDefaults.standard.object(
                    forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled
                ) as? Bool ?? true
                if autoSync {
                    syncQueue.startAutoSync()
                }
                BackgroundSyncScheduler.scheduleNextSync()
                _ = NetworkMonitor.shared
            }
            .onChange(of: scenePhase) { _, phase in
                // Keep the BG refresh chain alive; do not sync on resume or background.
                if phase == .active || phase == .background {
                    BackgroundSyncScheduler.scheduleNextSync()
                }
            }
    }
}
