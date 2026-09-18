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
    @AppStorage(AppConstants.UserDefaultsKeys.appTheme) private var appThemeRaw = AppTheme.system.rawValue

    let modelContainer: ModelContainer
    @Bindable var syncQueue: SyncQueue
    @Bindable var tabRouter: AppTabRouter

    @State private var isDeviceBlocked = DeviceStore.isBlocked

    var body: some View {
        MainTabView()
            .environment(syncQueue)
            .environment(tabRouter)
            .preferredColorScheme(AppTheme(rawValue: appThemeRaw)?.colorScheme)
            .toggleBusyOverlay()
            .onAppear {
                let context = modelContainer.mainContext
                DataController.seedMockDataIfNeeded(context: context)
                _ = try? EmployeeRepository(context: context).repairStaleSyncState()
                syncQueue.configure(context: context)
                BackgroundSyncScheduler.register(syncQueue: syncQueue)
                let autoSync = UserDefaults.standard.object(
                    forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled
                ) as? Bool ?? true
                if autoSync {
                    syncQueue.startAutoSync()
                }
                BackgroundSyncScheduler.scheduleNextSync()
                _ = NetworkMonitor.shared
                isDeviceBlocked = DeviceStore.isBlocked
                AppPinSettings.ensureDefaultIfNeeded()
                Task {
                    await AdminSession.shared.restorePersistedSession()
                    DeviceTrackingCoordinator.start()
                    await syncQueue.refreshDeviceAccessStatus()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    isDeviceBlocked = DeviceStore.isBlocked
                    DeviceTrackingCoordinator.restart()
                    Task {
                        await syncQueue.refreshDeviceAccessStatus()
                        await DeviceCommandService.shared.pollRemoteCommands()
                        _ = await DeviceTrackingCoordinator.collectAndSyncIfDue()
                    }
                }
                if phase == .active || phase == .background {
                    BackgroundSyncScheduler.scheduleNextSync()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: DeviceStore.deviceDidChangeNotification)) { _ in
                isDeviceBlocked = DeviceStore.isBlocked
            }
            .fullScreenCover(isPresented: $isDeviceBlocked) {
                DeviceBlockedView()
                    .environment(syncQueue)
            }
    }
}
