//
//  AttendanceHistoryViewModel.swift
//  ConsTrac
//

import Foundation
import SwiftData

@MainActor
@Observable
final class AttendanceHistoryViewModel {
    var filterCheckType: CheckType?
    var showPendingOnly = true

    private(set) var records: [HistoryItem] = []
    private(set) var totalRecordCount = 0
    private(set) var errorMessage: String?
    private(set) var didClear = false

    private var attendanceService: AttendanceService?

    struct HistoryItem: Identifiable {
        let id: UUID
        let employeeName: String
        let employeeCode: String
        let checkType: CheckType
        let timestamp: Date
        let syncStatus: SyncStatus
        let confidence: Double
    }

    func configure(context: ModelContext) {
        attendanceService = AttendanceService(context: context)
        refresh()
    }

    func refresh() {
        guard let attendanceService else { return }
        do {
            let all = try attendanceService.history()
            totalRecordCount = all.count
            var fetched = all
            if let filterCheckType {
                fetched = fetched.filter { $0.checkType == filterCheckType }
            }
            if showPendingOnly {
                fetched = fetched.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }
            }
            records = fetched.map { record in
                HistoryItem(
                    id: record.id,
                    employeeName: attendanceService.employeeName(for: record),
                    employeeCode: attendanceService.employeeCode(for: record),
                    checkType: record.checkType,
                    timestamp: record.timestamp,
                    syncStatus: record.syncStatus,
                    confidence: record.confidenceScore
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears the sync-history UI list only. Does NOT delete DTR Time In / Time Out records.
    func clearHistory() {
        records = []
        didClear = true
        errorMessage = nil
        // Intentionally does not call attendanceService.clearHistory() — DTR must remain intact.
    }
}
