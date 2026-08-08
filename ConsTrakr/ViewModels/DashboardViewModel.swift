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
    private(set) var defaultSiteId: UUID?

    private var employeeService: EmployeeService?
    private var attendanceService: AttendanceService?
    private var syncQueue: SyncQueue?

    var sitesNeedingAttention: [SiteAttendanceSummary] {
        guard let defaultSiteId else { return [] }
        return siteSummaries.filter { site in
            guard site.id == defaultSiteId, site.assignedCount > 0 else { return false }
            return (site.coveragePercent ?? 100) < 70 || site.absentCount > 0
        }
    }

    var defaultSiteSummary: SiteAttendanceSummary? {
        guard let defaultSiteId else { return nil }
        return siteSummaries.first { $0.id == defaultSiteId }
    }

    struct SiteAttendanceSummary: Identifiable {
        let id: UUID
        let siteName: String
        let locationLabel: String
        let assignedCount: Int
        let checkInCount: Int
        let checkOutCount: Int
        let absentCount: Int
        let incompleteCount: Int
        /// In + out = 1.0, in only = 0.5, absent = 0.
        let completionScore: Double

        var coveragePercent: Int? {
            guard assignedCount > 0 else { return nil }
            return Int((completionScore * 100 / Double(assignedCount)).rounded())
        }

        var inOutLine: String {
            "In (\(checkInCount)) | Out (\(checkOutCount))"
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
        var checkInCount = 0
        var checkOutCount = 0
        var absent = 0
        var incomplete = 0
        var completionScore: Double = 0

        var coveragePercent: Int? {
            guard assigned > 0 else { return nil }
            return Int((completionScore * 100 / Double(assigned)).rounded())
        }

        var inOutLine: String {
            "In (\(checkInCount)) | Out (\(checkOutCount))"
        }

        var completionFractionLine: String {
            "\(Self.formatScore(completionScore))/\(assigned)"
        }

        private static func formatScore(_ score: Double) -> String {
            if score.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(score))
            }
            return String(format: "%.1f", score)
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
        defaultSiteId = JobSiteStore.defaultSiteId ?? JobSiteStore.defaultSite?.id
        do {
            let employees = try employeeService.allEmployees()
            if let defaultSiteId {
                enrolledCount = employees.filter { $0.isEnrolled && $0.assignedSiteId == defaultSiteId }.count
                employeeCount = employees.filter { $0.assignedSiteId == defaultSiteId }.count
                unassignedCount = employees.filter { $0.assignedSiteId == nil }.count
            } else {
                enrolledCount = 0
                employeeCount = 0
                unassignedCount = employees.filter { $0.assignedSiteId == nil }.count
            }
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
            for record in todayRecords {
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

            let sitesToShow: [JobSite]
            if let defaultSiteId, let defaultSite = JobSiteStore.site(id: defaultSiteId) {
                sitesToShow = [defaultSite]
            } else {
                sitesToShow = []
            }

            for site in sitesToShow {
                let assigned = employees.filter { $0.assignedSiteId == site.id }
                var checkInCount = 0
                var checkOutCount = 0
                var absentCount = 0
                var incompleteCount = 0
                var completionScore = 0.0

                for employee in assigned {
                    let state = punchState[employee.id]
                    let hasIn = state?.hasIn == true
                    let hasOut = state?.hasOut == true

                    if hasIn {
                        checkInCount += 1
                        if hasOut {
                            completionScore += 1.0
                        } else {
                            incompleteCount += 1
                            completionScore += 0.5
                        }
                    } else {
                        absentCount += 1
                    }
                    if hasOut {
                        checkOutCount += 1
                    }
                }

                totals.assigned += assigned.count
                totals.checkInCount += checkInCount
                totals.checkOutCount += checkOutCount
                totals.absent += absentCount
                totals.incomplete += incompleteCount
                totals.completionScore += completionScore

                summaries.append(
                    SiteAttendanceSummary(
                        id: site.id,
                        siteName: site.displayTitle,
                        locationLabel: site.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        assignedCount: assigned.count,
                        checkInCount: checkInCount,
                        checkOutCount: checkOutCount,
                        absentCount: absentCount,
                        incompleteCount: incompleteCount,
                        completionScore: completionScore
                    )
                )
            }

            siteSummaries = summaries
            attendanceTotals = totals
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncNow() async {
        await syncQueue?.syncNow(mode: .quick, scope: .all)
        refresh()
    }
}
