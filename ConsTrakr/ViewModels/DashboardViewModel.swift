//
//  DashboardViewModel.swift
//  ConsTrakr
//

import Foundation
import SwiftData

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var employeeCount = 0
    private(set) var todayAttendanceCount = 0
    private(set) var pendingSyncCount = 0
    private(set) var recentAttendance: [AttendanceDisplayItem] = []
    private(set) var isOnline = false
    private(set) var errorMessage: String?

    private var employeeService: EmployeeService?
    private var attendanceService: AttendanceService?
    private var syncQueue: SyncQueue?

    struct AttendanceDisplayItem: Identifiable {
        let id: UUID
        let name: String
        let code: String
        let checkType: CheckType
        let timestamp: Date
        let syncStatus: SyncStatus
    }

    func configure(context: ModelContext, syncQueue: SyncQueue) {
        employeeService = EmployeeService(context: context)
        attendanceService = AttendanceService(context: context)
        self.syncQueue = syncQueue
        refresh()
    }

    func refresh() {
        guard let employeeService, let attendanceService else { return }
        do {
            employeeCount = try employeeService.count()
            todayAttendanceCount = try attendanceService.todayCount()
            if let syncPending = syncQueue?.pendingCount {
                pendingSyncCount = syncPending
            } else {
                pendingSyncCount = try attendanceService.pendingSyncCount()
            }
            isOnline = NetworkMonitor.shared.isConnected

            let recent = try attendanceService.history().prefix(5)
            recentAttendance = recent.map { record in
                AttendanceDisplayItem(
                    id: record.id,
                    name: attendanceService.employeeName(for: record),
                    code: attendanceService.employeeCode(for: record),
                    checkType: record.checkType,
                    timestamp: record.timestamp,
                    syncStatus: record.syncStatus
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
