//
//  BackgroundSyncScheduler.swift
//  ConsTrakr
//
//  Foreground timer (5 min) + BGAppRefresh + flush when app backgrounds.
//

import BackgroundTasks
import UIKit

@MainActor
enum BackgroundSyncScheduler {
    /// Must match BGTaskSchedulerPermittedIdentifiers in BackgroundInfo.plist.
    static let taskIdentifier = "Admin.ConsTrakr.sync.refresh"

    private static weak var syncQueue: SyncQueue?

    static func register(syncQueue: SyncQueue) {
        self.syncQueue = syncQueue

        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handleAppRefresh(refreshTask)
            }
        }
    }

    /// Ask iOS to wake the app for sync (~1 min earliest; iOS may defer on battery).
    static func scheduleNextSync(after seconds: TimeInterval = AppConstants.syncIntervalSeconds) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(60, seconds))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator / restricted background — foreground timer still runs.
        }
    }

    /// Run sync when returning to foreground.
    static func syncOnBecomeActive() {
        guard let syncQueue else { return }
        scheduleNextSync()
        Task {
            await syncQueue.syncIfNeeded()
        }
    }

    /// Best-effort upload when user leaves the app (~30s background time).
    static func syncBeforeBackground() {
        guard let syncQueue else { return }
        scheduleNextSync()

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ConsTrakrSync") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        guard backgroundTaskID != .invalid else { return }

        Task {
            await syncQueue.syncIfNeeded()
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }
    }

    private static func handleAppRefresh(_ task: BGAppRefreshTask) async {
        scheduleNextSync()

        let work = Task {
            await syncQueue?.syncIfNeeded()
        }

        task.expirationHandler = {
            work.cancel()
        }

        await work.value
        let ok = syncQueue?.lastError == nil || syncQueue?.pendingCount == 0
        task.setTaskCompleted(success: ok)
    }
}
