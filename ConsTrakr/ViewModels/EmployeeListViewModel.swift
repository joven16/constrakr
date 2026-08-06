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
    private(set) var errorMessage: String?
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
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cloudStatus(for employeeId: UUID) -> EmployeeCloudStatus {
        cloudReport?.status(for: employeeId) ?? .notChecked
    }

    func checkCloudSync() async {
        guard let modelContext else { return }
        isCheckingCloud = true
        defer {
            isCheckingCloud = false
            refresh()
        }

        do {
            if let syncQueue {
                cloudReport = try await syncQueue.checkEmployeesOnIMS()
            } else {
                cloudReport = try await EmployeeSyncChecker.check(context: modelContext, repair: true)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ employee: Employee) {
        guard let employeeService else { return }
        do {
            try employeeService.delete(employee)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
