//
//  EmployeeIdDocumentEntity.swift
//  ConsTrakr
//
//  Syncable government ID metadata + photo upload queue (one per employee).
//

import Foundation
import SwiftData

@Model
final class EmployeeIdDocumentEntity {
    @Attribute(.unique) var id: UUID
    var employeeLocalId: UUID
    var employeeServerId: String?
    var idTypeRaw: String
    var idNumber: String
    var capturedAt: Date?
    var syncStatusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        employeeLocalId: UUID,
        employeeServerId: String? = nil,
        idType: IdDocumentType,
        idNumber: String = "",
        capturedAt: Date? = nil,
        syncStatus: SyncStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.employeeLocalId = employeeLocalId
        self.employeeServerId = employeeServerId
        self.idTypeRaw = idType.rawValue
        self.idNumber = idNumber
        self.capturedAt = capturedAt
        self.syncStatusRaw = syncStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var idType: IdDocumentType {
        get { IdDocumentType(rawValue: idTypeRaw) ?? .philsysNationalId }
        set { idTypeRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}
