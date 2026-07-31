//
//  AttendanceService.swift
//  ConsTrac
//

import Foundation
import SwiftData

@MainActor
final class AttendanceService {
    private let repository: AttendanceRepository
    private let employeeRepository: EmployeeRepository

    init(context: ModelContext) {
        self.repository = AttendanceRepository(context: context)
        self.employeeRepository = EmployeeRepository(context: context)
    }

    func record(
        employeeId: UUID,
        checkType: CheckType,
        confidence: Double,
        notes: String? = nil
    ) throws -> Attendance {
        if try repository.hasRecordedToday(employeeId: employeeId, checkType: checkType) {
            throw ServiceError.alreadyRecordedToday(checkType)
        }

        // Resolve employeeServerId when available so POST /attendance can link remotely.
        let employeeServerId = try employeeRepository.fetch(id: employeeId)?.serverId

        // Offline-first: always save locally as pending.
        let attendance = Attendance(
            employeeId: employeeId,
            employeeServerId: employeeServerId,
            checkType: checkType,
            timestamp: Date(),
            syncStatus: .pending,
            confidenceScore: confidence,
            notes: notes
        )
        try repository.save(attendance)
        return attendance
    }

    func hasRecordedToday(employeeId: UUID, checkType: CheckType) throws -> Bool {
        try repository.hasRecordedToday(employeeId: employeeId, checkType: checkType)
    }

    func todaysRecord(employeeId: UUID, checkType: CheckType) throws -> Attendance? {
        try repository.todaysRecord(employeeId: employeeId, checkType: checkType)
    }

    func history(
        employeeId: UUID? = nil,
        from: Date? = nil,
        to: Date? = nil
    ) throws -> [Attendance] {
        try repository.fetchAll(employeeId: employeeId, from: from, to: to)
    }

    func todayCount() throws -> Int {
        try repository.todayCount()
    }

    func pendingSyncCount() throws -> Int {
        try repository.pendingCount()
    }

    func employeeName(for attendance: Attendance) -> String {
        (try? employeeRepository.fetch(id: attendance.employeeId))?.fullName ?? "Unknown"
    }

    func employeeCode(for attendance: Attendance) -> String {
        (try? employeeRepository.fetch(id: attendance.employeeId))?.employeeCode ?? "—"
    }

    /// Wipe every Time In and Time Out record from local storage.
    func clearHistory() throws {
        try repository.deleteAll()
        NotificationCenter.default.post(name: AppConstants.Notifications.attendanceHistoryDidClear, object: nil)
    }

    enum ServiceError: LocalizedError {
        case alreadyRecordedToday(CheckType)

        var errorDescription: String? {
            switch self {
            case .alreadyRecordedToday(.checkIn):
                return "Already timed in today. Only one Time In is allowed per day."
            case .alreadyRecordedToday(.checkOut):
                return "Already timed out today. Only one Time Out is allowed per day."
            }
        }
    }
}
