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
    private(set) var viewSiteId: UUID?
    private(set) var viewSiteTitle: String?

    private(set) var cloudReport: EmployeeSyncReport?
    private(set) var isCheckingCloud = false
    private(set) var cloudCheckErrorMessage: String?

    private var modelContext: ModelContext?
    private var syncQueue: SyncQueue?
    private var employeeService: EmployeeService?
    private let refreshDebouncer = RefreshDebouncer(delayMilliseconds: 250)
    private let searchDebouncer = RefreshDebouncer(delayMilliseconds: 300)

    func configure(context: ModelContext, syncQueue: SyncQueue? = nil) {
        modelContext = context
        self.syncQueue = syncQueue
        employeeService = EmployeeService(context: context)
        refresh()
    }

    func refreshDebounced() {
        refreshDebouncer.schedule { [weak self] in
            self?.refresh()
        }
    }

    func searchTextChanged() {
        searchDebouncer.schedule { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        guard let employeeService else { return }
        let filterSiteId = AppAccessSession.shared.effectiveViewSiteId
        viewSiteId = filterSiteId
        if let filterSiteId, let site = JobSiteStore.site(id: filterSiteId) {
            viewSiteTitle = site.displayTitle
        } else {
            viewSiteTitle = nil
        }
        do {
            var list = try employeeService.allEmployees(search: searchText)
            if let filterSiteId {
                list = list.filter { $0.assignedSiteId == filterSiteId }
            } else {
                list = []
            }
            employees = list
            listErrorMessage = nil
        } catch {
            listErrorMessage = error.localizedDescription
        }
    }

    private func reloadEmployeesOnly() {
        refresh()
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

        await syncQueue?.syncNow(mode: .quick, scope: .employees)
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
