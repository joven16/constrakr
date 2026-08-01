//
//  Attendance.swift
//  ConsTrakr
//
//  CHANGE: Added `serverId` so local UUIDs stay separate from backend ids.
//

import Foundation
import SwiftData

@Model
final class Attendance {
    /// Local-only primary key.
    @Attribute(.unique) var id: UUID
    /// Backend id after POST /attendance — nil until synced.
    var serverId: String?
    var employeeId: UUID
    /// Optional backend employee id for upload payloads after employee sync.
    var employeeServerId: String?
    var checkTypeRaw: String
    var timestamp: Date
    var syncStatusRaw: String
    var confidenceScore: Double
    var notes: String?

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        employeeId: UUID,
        employeeServerId: String? = nil,
        checkType: CheckType,
        timestamp: Date = Date(),
        syncStatus: SyncStatus = .pending,
        confidenceScore: Double = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.employeeId = employeeId
        self.employeeServerId = employeeServerId
        self.checkTypeRaw = checkType.rawValue
        self.timestamp = timestamp
        self.syncStatusRaw = syncStatus.rawValue
        self.confidenceScore = confidenceScore
        self.notes = notes
    }

    var checkType: CheckType {
        get { CheckType(rawValue: checkTypeRaw) ?? .checkIn }
        set { checkTypeRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}
