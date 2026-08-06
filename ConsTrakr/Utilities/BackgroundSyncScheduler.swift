//
//  BackgroundSyncScheduler.swift
//  ConsTrakr
//
//  Foreground timer (user interval) + BGAppRefresh on the same schedule.
//  Does not sync on app resume or when leaving the app — only on the timer,
//  manual Sync Now, and iOS background refresh.
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

    /// Ask iOS to wake the app for sync (earliest = user interval; iOS may defer on battery).
    static func scheduleNextSync(after seconds: TimeInterval? = nil) {
        let interval = seconds ?? SyncSettings.intervalSeconds
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(60, interval))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator / restricted background — foreground timer still runs.
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
