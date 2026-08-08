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
    private(set) var enrolledCount = 0
    private(set) var unassignedCount = 0
    private(set) var pendingSyncCount = 0
    private(set) var siteSummaries: [SiteAttendanceSummary] = []
    private(set) var attendanceTotals = AttendanceTotals()
    private(set) var isOnline = false
    private(set) var errorMessage: String?

    private var employeeService: EmployeeService?
    private var attendanceService: AttendanceService?
    private var syncQueue: SyncQueue?

    var sitesNeedingAttention: [SiteAttendanceSummary] {
        siteSummaries.filter { site in
            guard site.assignedCount > 0, let percent = site.coveragePercent else { return false }
            return percent < 70 || site.absentCount > 0
        }
    }

    struct SiteAttendanceSummary: Identifiable {
        let id: UUID
        let siteName: String
        let locationLabel: String
        let assignedCount: Int
        let presentCount: Int
        let absentCount: Int
        let incompleteCount: Int
        let punchCount: Int

        var coveragePercent: Int? {
            guard assignedCount > 0 else { return nil }
            return Int((Double(presentCount) * 100 / Double(assignedCount)).rounded())
        }

        enum CoverageLevel {
            case none
            case good
            case warning
            case critical
        }

        var coverageLevel: CoverageLevel {
            guard let coveragePercent else { return .none }
            if coveragePercent >= 90 { return .good }
            if coveragePercent >= 70 { return .warning }
            return .critical
        }
    }

    struct AttendanceTotals {
        var assigned = 0
        var present = 0
        var absent = 0
        var incomplete = 0
        var punchCount = 0

        var coveragePercent: Int? {
            guard assigned > 0 else { return nil }
            return Int((Double(present) * 100 / Double(assigned)).rounded())
        }
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
            let employees = try employeeService.allEmployees()
            enrolledCount = employees.filter(\.isEnrolled).count
            unassignedCount = employees.filter { $0.assignedSiteId == nil }.count
            if let syncPending = syncQueue?.pendingCount {
                pendingSyncCount = syncPending
            } else {
                pendingSyncCount = try attendanceService.pendingSyncCount()
            }
            isOnline = NetworkMonitor.shared.isConnected

            let calendar = Calendar.current
            let start = calendar.startOfDay(for: Date())
            let end = calendar.date(byAdding: .day, value: 1, to: start)?
                .addingTimeInterval(-0.001) ?? start
            let todayRecords = try attendanceService.history(from: start, to: end)

            var punchState: [UUID: (hasIn: Bool, hasOut: Bool)] = [:]
            var punchCountByEmployee: [UUID: Int] = [:]
            for record in todayRecords {
                punchCountByEmployee[record.employeeId, default: 0] += 1
                var state = punchState[record.employeeId] ?? (false, false)
                switch record.checkType {
                case .checkIn:
                    state.hasIn = true
                case .checkOut:
                    state.hasOut = true
                }
                punchState[record.employeeId] = state
            }

            var totals = AttendanceTotals()
            var summaries: [SiteAttendanceSummary] = []

            for site in JobSiteStore.allSites {
                let assigned = employees.filter { $0.assignedSiteId == site.id }
                var presentCount = 0
                var absentCount = 0
                var incompleteCount = 0
                var punchCount = 0

                for employee in assigned {
                    let state = punchState[employee.id]
                    if state?.hasIn == true {
                        presentCount += 1
                        if state?.hasOut != true {
                            incompleteCount += 1
                        }
                    } else {
                        absentCount += 1
                    }
                    punchCount += punchCountByEmployee[employee.id] ?? 0
                }

                totals.assigned += assigned.count
                totals.present += presentCount
                totals.absent += absentCount
                totals.incomplete += incompleteCount
                totals.punchCount += punchCount

                summaries.append(
                    SiteAttendanceSummary(
                        id: site.id,
                        siteName: site.displayTitle,
                        locationLabel: site.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        assignedCount: assigned.count,
                        presentCount: presentCount,
                        absentCount: absentCount,
                        incompleteCount: incompleteCount,
                        punchCount: punchCount
                    )
                )
            }

            summaries.sort { lhs, rhs in
                if lhs.assignedCount == 0, rhs.assignedCount > 0 { return false }
                if rhs.assignedCount == 0, lhs.assignedCount > 0 { return true }
                let left = lhs.coveragePercent ?? 101
                let right = rhs.coveragePercent ?? 101
                if left != right { return left < right }
                return lhs.siteName.localizedCaseInsensitiveCompare(rhs.siteName) == .orderedAscending
            }

            siteSummaries = summaries
            attendanceTotals = totals
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
