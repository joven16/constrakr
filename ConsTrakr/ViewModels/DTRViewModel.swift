//
//  DTRViewModel.swift
//  ConsTrakr
//

import Foundation
import SwiftData

@MainActor
@Observable
final class DTRViewModel {
    var selectedDate: Date = Date()

    private(set) var rows: [DTRRow] = []
    private(set) var errorMessage: String?
    private(set) var pendingSyncCount = 0
    private(set) var isSyncing = false
    private(set) var isOnline = false
    private(set) var syncStatusMessage: String?
    private(set) var lastSyncDate: Date?
    private(set) var cloudReport: EmployeeSyncReport?

    private var attendanceService: AttendanceService?
    private var syncQueue: SyncQueue?
    private var modelContext: ModelContext?

    struct DTRRow: Identifiable {
        let id: UUID
        let employeeName: String
        let employeeCode: String
        let timeIn: Date?
        let timeOut: Date?
        let timeInAttendanceId: UUID?
        let timeOutAttendanceId: UUID?
    }

    var dayTitle: String {
        selectedDate.formatted(date: .complete, time: .omitted)
    }

    func configure(context: ModelContext, syncQueue: SyncQueue) {
        attendanceService = AttendanceService(context: context)
        modelContext = context
        self.syncQueue = syncQueue
        refresh()
    }

    func syncNow() async {
        guard AdminSession.shared.isAuthenticated else {
            syncStatusMessage = "Sign in under More → Settings → IMS Sync & Restore."
            return
        }

        isSyncing = true
        syncStatusMessage = "Syncing employees, face data, and DTR…"
        defer {
            isSyncing = syncQueue?.isSyncing ?? false
            refresh()
        }

        await syncQueue?.syncNow()

        cloudReport = syncQueue?.lastEmployeeSyncReport

        if let error = syncQueue?.lastError, !error.isEmpty {
            syncStatusMessage = error
        } else if let summary = syncQueue?.lastPushSummary {
            syncStatusMessage = summary.successMessage
            lastSyncDate = syncQueue?.lastSyncDate
        } else {
            let unsynced: Int
            if let modelContext {
                unsynced = (try? EmployeeRepository(context: modelContext).fetchPendingSync().count) ?? 0
            } else {
                unsynced = 0
            }
            if unsynced > 0 {
                syncStatusMessage = "Sync finished but \(unsynced) employee(s) still not uploaded. Check sign-in and try again."
            } else if syncQueue?.lastPushSummary == nil {
                syncStatusMessage = "Sync complete — employees and DTR uploaded."
            }
            lastSyncDate = syncQueue?.lastSyncDate
        }
    }

    func refresh() {
        guard let attendanceService else { return }
        pendingSyncCount = syncQueue?.pendingCount ?? 0
        isSyncing = syncQueue?.isSyncing ?? false
        isOnline = NetworkMonitor.shared.isConnected
        lastSyncDate = syncQueue?.lastSyncDate
        if syncStatusMessage == nil, let error = syncQueue?.lastError, !error.isEmpty {
            syncStatusMessage = error
        }

        do {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)?
                .addingTimeInterval(-0.001) ?? start

            let fetched = try attendanceService.history(from: start, to: end)

            struct Acc {
                var name: String
                var code: String
                var timeIn: Date?
                var timeOut: Date?
                var timeInAttendanceId: UUID?
                var timeOutAttendanceId: UUID?
            }

            var byEmployee: [UUID: Acc] = [:]
            for record in fetched {
                var acc = byEmployee[record.employeeId] ?? Acc(
                    name: attendanceService.employeeName(for: record),
                    code: attendanceService.employeeCode(for: record),
                    timeIn: nil,
                    timeOut: nil,
                    timeInAttendanceId: nil,
                    timeOutAttendanceId: nil
                )
                switch record.checkType {
                case .checkIn:
                    if acc.timeIn == nil || record.timestamp < acc.timeIn! {
                        acc.timeIn = record.timestamp
                        acc.timeInAttendanceId = record.id
                    }
                case .checkOut:
                    if acc.timeOut == nil || record.timestamp > acc.timeOut! {
                        acc.timeOut = record.timestamp
                        acc.timeOutAttendanceId = record.id
                    }
                }
                byEmployee[record.employeeId] = acc
            }

            rows = byEmployee.map { id, acc in
                DTRRow(
                    id: id,
                    employeeName: acc.name,
                    employeeCode: acc.code,
                    timeIn: acc.timeIn,
                    timeOut: acc.timeOut,
                    timeInAttendanceId: acc.timeInAttendanceId,
                    timeOutAttendanceId: acc.timeOutAttendanceId
                )
            }
            .sorted { $0.employeeName.localizedCaseInsensitiveCompare($1.employeeName) == .orderedAscending }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
