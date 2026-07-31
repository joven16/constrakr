//
//  AttendanceRepository.swift
//  ConsTrac
//

import Foundation
import SwiftData

@MainActor
final class AttendanceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll(
        employeeId: UUID? = nil,
        from start: Date? = nil,
        to end: Date? = nil
    ) throws -> [Attendance] {
        var descriptor = FetchDescriptor<Attendance>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        if let employeeId, let start, let end {
            descriptor.predicate = #Predicate { record in
                record.employeeId == employeeId
                    && record.timestamp >= start
                    && record.timestamp <= end
            }
        } else if let employeeId {
            descriptor.predicate = #Predicate { $0.employeeId == employeeId }
        } else if let start, let end {
            descriptor.predicate = #Predicate { record in
                record.timestamp >= start && record.timestamp <= end
            }
        }

        return try context.fetch(descriptor)
    }

    func fetchPendingSync() throws -> [Attendance] {
        let pending = SyncStatus.pending.rawValue
        let failed = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<Attendance>(
            predicate: #Predicate { record in
                (record.syncStatusRaw == pending || record.syncStatusRaw == failed)
                    && record.serverId == nil
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try context.fetch(descriptor)
    }

    func todayCount() throws -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Attendance>(
            predicate: #Predicate { $0.timestamp >= start }
        )
        return try context.fetchCount(descriptor)
    }

    /// True if this employee already has the given check type recorded today.
    func hasRecordedToday(employeeId: UUID, checkType: CheckType) throws -> Bool {
        try todaysRecord(employeeId: employeeId, checkType: checkType) != nil
    }

    /// Today's attendance record for this employee and check type, if any.
    func todaysRecord(employeeId: UUID, checkType: CheckType) throws -> Attendance? {
        let start = Calendar.current.startOfDay(for: Date())
        let checkTypeRaw = checkType.rawValue
        var descriptor = FetchDescriptor<Attendance>(
            predicate: #Predicate { record in
                record.employeeId == employeeId
                    && record.checkTypeRaw == checkTypeRaw
                    && record.timestamp >= start
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func save(_ attendance: Attendance) throws {
        context.insert(attendance)
        try context.save()
    }

    func updateSyncStatus(_ attendance: Attendance, status: SyncStatus) throws {
        attendance.syncStatus = status
        try context.save()
    }

    func pendingCount() throws -> Int {
        let pending = SyncStatus.pending.rawValue
        let failed = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<Attendance>(
            predicate: #Predicate { record in
                (record.syncStatusRaw == pending || record.syncStatusRaw == failed)
                    && record.serverId == nil
            }
        )
        return try context.fetchCount(descriptor)
    }

    /// CHANGE: Clears all local Time In / Time Out records (Dashboard + History + scanner cache).
    func deleteAll() throws {
        let descriptor = FetchDescriptor<Attendance>()
        let all = try context.fetch(descriptor)
        for record in all {
            context.delete(record)
        }
        try context.save()
    }
}
