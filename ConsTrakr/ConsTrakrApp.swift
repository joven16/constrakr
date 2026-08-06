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
            AppRootView(
                modelContainer: modelContainer,
                syncQueue: syncQueue,
                tabRouter: tabRouter
            )
        }
        .modelContainer(modelContainer)
    }
}
