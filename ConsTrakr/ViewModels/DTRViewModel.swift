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
    private(set) var isOnline = false
    private(set) var lastSyncDate: Date?
    private(set) var defaultSiteId: UUID?

    private var attendanceService: AttendanceService?
    private var employeeService: EmployeeService?
    private var syncQueue: SyncQueue?

    struct DTRRow: Identifiable {
        let id: UUID
        let employeeName: String
        let employeeCode: String
        let timeIn: Date?
        let timeOut: Date?
        let timeInAttendanceId: UUID?
        let timeOutAttendanceId: UUID?
        let timeInCorrected: Bool
        let timeOutCorrected: Bool
    }

    var dayTitle: String {
        selectedDate.formatted(date: .complete, time: .omitted)
    }

    var selectedSiteTitle: String? {
        guard let defaultSiteId else { return nil }
        return JobSiteStore.site(id: defaultSiteId)?.displayTitle
    }

    func configure(context: ModelContext, syncQueue: SyncQueue) {
        attendanceService = AttendanceService(context: context)
        employeeService = EmployeeService(context: context)
        self.syncQueue = syncQueue
        refresh()
    }

    func refresh() {
        guard let attendanceService, let employeeService else { return }
        defaultSiteId = JobSiteStore.defaultSiteId ?? JobSiteStore.defaultSite?.id
        pendingSyncCount = syncQueue?.pendingCount ?? 0
        isOnline = NetworkMonitor.shared.isConnected
        lastSyncDate = syncQueue?.lastSyncDate

        guard let defaultSiteId else {
            rows = []
            errorMessage = nil
            return
        }

        do {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)?
                .addingTimeInterval(-0.001) ?? start

            let assignedEmployees = try employeeService.allEmployees()
                .filter { $0.assignedSiteId == defaultSiteId }
                .sorted {
                    $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
                }

            let employeeIds = Set(assignedEmployees.map(\.id))
            let fetched = try attendanceService.history(from: start, to: end)
                .filter { employeeIds.contains($0.employeeId) }

            struct Acc {
                var name: String
                var code: String
                var timeIn: Date?
                var timeOut: Date?
                var timeInAttendanceId: UUID?
                var timeOutAttendanceId: UUID?
                var timeInCorrected = false
                var timeOutCorrected = false
            }

            var byEmployee: [UUID: Acc] = [:]
            for employee in assignedEmployees {
                byEmployee[employee.id] = Acc(
                    name: employee.fullName,
                    code: employee.employeeCode,
                    timeIn: nil,
                    timeOut: nil,
                    timeInAttendanceId: nil,
                    timeOutAttendanceId: nil
                )
            }

            for record in fetched {
                guard var acc = byEmployee[record.employeeId] else { continue }
                let isManual = Self.isManualCorrection(record)
                switch record.checkType {
                case .checkIn:
                    if acc.timeIn == nil || record.timestamp < acc.timeIn! {
                        acc.timeIn = record.timestamp
                        acc.timeInAttendanceId = record.id
                        acc.timeInCorrected = isManual
                    }
                case .checkOut:
                    if acc.timeOut == nil || record.timestamp > acc.timeOut! {
                        acc.timeOut = record.timestamp
                        acc.timeOutAttendanceId = record.id
                        acc.timeOutCorrected = isManual
                    }
                }
                byEmployee[record.employeeId] = acc
            }

            rows = assignedEmployees.compactMap { employee in
                guard let acc = byEmployee[employee.id] else { return nil }
                return DTRRow(
                    id: employee.id,
                    employeeName: acc.name,
                    employeeCode: acc.code,
                    timeIn: acc.timeIn,
                    timeOut: acc.timeOut,
                    timeInAttendanceId: acc.timeInAttendanceId,
                    timeOutAttendanceId: acc.timeOutAttendanceId,
                    timeInCorrected: acc.timeInCorrected,
                    timeOutCorrected: acc.timeOutCorrected
                )
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Upload pending punches and pull IMS corrections for the selected DTR day.
    func syncNow() async {
        await syncQueue?.syncNow(mode: .quick, scope: .attendance, dtrFocusDate: selectedDate)
        refresh()
    }

    private static func isManualCorrection(_ record: Attendance) -> Bool {
        guard let notes = record.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else {
            return false
        }
        return notes.localizedCaseInsensitiveContains("manual dtr")
    }
}
