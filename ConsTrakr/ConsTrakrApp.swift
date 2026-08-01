//
//  ConsTrakrApp.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

@main
struct ConsTrakrApp: App {
    private let modelContainer: ModelContainer
    @State private var syncQueue = SyncQueue()
    @State private var tabRouter = AppTabRouter()

    init() {
        modelContainer = DataController.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(syncQueue)
                .environment(tabRouter)
                .onAppear {
                    let context = modelContainer.mainContext
                    DataController.seedMockDataIfNeeded(context: context)
                    syncQueue.configure(context: context)
                    let autoSync = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.autoSyncEnabled) as? Bool ?? true
                    if autoSync {
                        syncQueue.startAutoSync()
                    }
                    // Warm NetworkMonitor
                    _ = NetworkMonitor.shared
                }
        }
        .modelContainer(modelContainer)
    }
}
