//
//  EmployeeListViewModel.swift
//  ConsTrakr
//

import Foundation
import SwiftData

@MainActor
@Observable
final class EmployeeListViewModel {
    var searchText = ""

    private(set) var employees: [Employee] = []
    private(set) var listErrorMessage: String?
    private(set) var cloudCheckErrorMessage: String?
    private(set) var cloudReport: EmployeeSyncReport?
    private(set) var isCheckingCloud = false

    private var employeeService: EmployeeService?
    private var modelContext: ModelContext?
    private var syncQueue: SyncQueue?

    func configure(context: ModelContext, syncQueue: SyncQueue? = nil) {
        modelContext = context
        self.syncQueue = syncQueue
        employeeService = EmployeeService(context: context)
        refresh()
    }

    func refresh() {
        guard let employeeService else { return }
        do {
            employees = try employeeService.allEmployees(search: searchText)
            listErrorMessage = nil
        } catch {
            listErrorMessage = error.localizedDescription
        }
    }

    private func reloadEmployeesOnly() {
        guard let employeeService else { return }
        employees = (try? employeeService.allEmployees(search: searchText)) ?? employees
    }

    func cloudStatus(for employeeId: UUID) -> EmployeeCloudStatus {
        cloudReport?.status(for: employeeId) ?? .notChecked
    }

    func cloudItem(for employeeId: UUID) -> EmployeeSyncStatusItem? {
        cloudReport?.item(for: employeeId)
    }

    /// Manual sync — check IMS, upload employees/embeddings/DTR, refresh status.
    func syncNow() async {
        guard syncQueue != nil else {
            cloudCheckErrorMessage = "Sync is not ready yet. Try again."
            return
        }
        isCheckingCloud = true
        defer {
            isCheckingCloud = false
            reloadEmployeesOnly()
        }

        await syncQueue?.syncNow(mode: .quick)
        cloudReport = syncQueue?.lastEmployeeSyncReport
        cloudCheckErrorMessage = syncQueue?.lastError
    }

    /// IMS status check only (no upload).
    func checkCloudOnly() async {
        guard let modelContext else {
            cloudCheckErrorMessage = "Employee list is not ready yet. Try again."
            return
        }
        isCheckingCloud = true
        defer {
            isCheckingCloud = false
            reloadEmployeesOnly()
        }

        do {
            if let syncQueue {
                cloudReport = try await syncQueue.checkEmployeesOnIMS()
            } else {
                cloudReport = try await EmployeeSyncChecker.check(context: modelContext, repair: true)
            }
            cloudCheckErrorMessage = nil
        } catch {
            cloudReport = nil
            cloudCheckErrorMessage = error.localizedDescription
        }
    }

    /// Check IMS status/dates, then run sync (same as manual Sync Now).
    func checkAndSyncCloud() async {
        await syncNow()
    }

    func checkCloudSync() async {
        await checkCloudOnly()
    }

    func applyCloudReport(_ report: EmployeeSyncReport?) {
        cloudReport = report
    }

    /// Refresh IMS badges when signed in — avoids stale "Not checked" on every row.
    func checkCloudIfNeeded() async {
        guard cloudReport == nil else { return }
        guard !isCheckingCloud else { return }
        await checkCloudOnly()
    }

    func delete(_ employee: Employee) async {
        guard let employeeService else { return }
        if let serverId = APIDecoding.normalizedServerId(employee.serverId) {
            PendingEmployeeDeletionStore.enqueue(serverId: serverId)
            await syncQueue?.service.processPendingEmployeeDeletions()
        }
        do {
            try employeeService.delete(employee)
            refresh()
        } catch {
            listErrorMessage = error.localizedDescription
        }
    }
}
