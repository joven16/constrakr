//
//  EmployeeIdDocumentRepository.swift
//  ConsTrakr
//

import Foundation
import SwiftData

@MainActor
final class EmployeeIdDocumentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetch(forEmployeeLocalId employeeLocalId: UUID) throws -> EmployeeIdDocumentEntity? {
        let descriptor = FetchDescriptor<EmployeeIdDocumentEntity>(
            predicate: #Predicate { $0.employeeLocalId == employeeLocalId }
        )
        return try context.fetch(descriptor).first
    }

    func fetchPendingSync() throws -> [EmployeeIdDocumentEntity] {
        let pending = SyncStatus.pending.rawValue
        let failed = SyncStatus.failed.rawValue
        let syncing = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<EmployeeIdDocumentEntity>(
            predicate: #Predicate { record in
                record.syncStatusRaw == pending
                    || record.syncStatusRaw == failed
                    || record.syncStatusRaw == syncing
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func repairStuckSync() throws -> Int {
        let syncing = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<EmployeeIdDocumentEntity>(
            predicate: #Predicate { $0.syncStatusRaw == syncing }
        )
        let stuck = try context.fetch(descriptor)
        for entity in stuck {
            entity.syncStatus = .pending
            entity.updatedAt = Date()
        }
        if !stuck.isEmpty {
            try context.save()
        }
        return stuck.count
    }

    func pendingCount() throws -> Int {
        try fetchPendingSync().count
    }

    func save(_ entity: EmployeeIdDocumentEntity) throws {
        context.insert(entity)
        try context.save()
    }

    func update(_ entity: EmployeeIdDocumentEntity, persist: Bool = true) throws {
        entity.updatedAt = Date()
        if persist {
            try context.save()
        }
    }

    func delete(forEmployeeLocalId employeeLocalId: UUID) throws {
        if let existing = try fetch(forEmployeeLocalId: employeeLocalId) {
            context.delete(existing)
            try context.save()
        }
    }

    func ensureEntityForEmployee(
        _ employee: Employee,
        idType: IdDocumentType,
        idNumber: String,
        capturedAt: Date?
    ) throws {
        if let existing = try fetch(forEmployeeLocalId: employee.id) {
            existing.idType = idType
            existing.idNumber = idNumber
            existing.capturedAt = capturedAt
            existing.employeeServerId = employee.serverId
            if existing.syncStatus == .synced {
                existing.syncStatus = .pending
            }
            try update(existing, persist: true)
            return
        }

        let entity = EmployeeIdDocumentEntity(
            employeeLocalId: employee.id,
            employeeServerId: employee.serverId,
            idType: idType,
            idNumber: idNumber,
            capturedAt: capturedAt,
            syncStatus: .pending
        )
        try save(entity)
    }

    func upsertFromRemote(_ dto: EmployeeIdDocumentDTO, employeeLocalId: UUID) throws {
        let idType = IdDocumentType(rawValue: dto.idType) ?? .others
        if let existing = try fetch(forEmployeeLocalId: employeeLocalId) {
            existing.idType = idType
            existing.idNumber = dto.idNumber ?? ""
            existing.capturedAt = dto.capturedAt
            existing.employeeServerId = dto.employeeServerId
            existing.syncStatus = .synced
            existing.updatedAt = Date()
        } else {
            let entity = EmployeeIdDocumentEntity(
                employeeLocalId: employeeLocalId,
                employeeServerId: dto.employeeServerId,
                idType: idType,
                idNumber: dto.idNumber ?? "",
                capturedAt: dto.capturedAt,
                syncStatus: .synced
            )
            context.insert(entity)
        }

        if let jpegBase64 = dto.jpegBase64,
           let jpeg = Data(base64Encoded: jpegBase64) {
            try IdDocumentPhotoStore.saveJPEG(jpeg, employeeId: employeeLocalId)
        }

        try context.save()
    }
}
