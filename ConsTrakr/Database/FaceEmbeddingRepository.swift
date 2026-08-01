//
//  FaceEmbeddingRepository.swift
//  ConsTrakr
//

import Foundation
import SwiftData

@MainActor
final class FaceEmbeddingRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetch(forEmployeeLocalId employeeLocalId: UUID) throws -> [FaceEmbeddingEntity] {
        let descriptor = FetchDescriptor<FaceEmbeddingEntity>(
            predicate: #Predicate { $0.employeeLocalId == employeeLocalId },
            sortBy: [SortDescriptor(\.poseRaw)]
        )
        return try context.fetch(descriptor)
    }

    func fetchPendingSync() throws -> [FaceEmbeddingEntity] {
        let pending = SyncStatus.pending.rawValue
        let failed = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<FaceEmbeddingEntity>(
            predicate: #Predicate { record in
                // Duplicate upload prevention: only pending/failed, never re-upload synced.
                (record.syncStatusRaw == pending || record.syncStatusRaw == failed)
                    && record.serverId == nil
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func pendingCount() throws -> Int {
        try fetchPendingSync().count
    }

    func save(_ entity: FaceEmbeddingEntity) throws {
        context.insert(entity)
        try context.save()
    }

    func saveAll(_ entities: [FaceEmbeddingEntity]) throws {
        entities.forEach { context.insert($0) }
        try context.save()
    }

    func update(_ entity: FaceEmbeddingEntity) throws {
        entity.updatedAt = Date()
        try context.save()
    }

    func delete(forEmployeeLocalId employeeLocalId: UUID) throws {
        let existing = try fetch(forEmployeeLocalId: employeeLocalId)
        existing.forEach { context.delete($0) }
        try context.save()
    }

    func upsertFromRemote(_ dto: FaceEmbeddingDTO, employeeLocalId: UUID) throws {
        // Prefer match by serverId to prevent duplicates on restore.
        if let serverId = dto.serverId {
            let descriptor = FetchDescriptor<FaceEmbeddingEntity>(
                predicate: #Predicate { $0.serverId == serverId }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.encryptedValues = Data(base64Encoded: dto.encryptedValuesBase64) ?? existing.encryptedValues
                existing.poseRaw = dto.pose
                existing.employeeLocalId = employeeLocalId
                existing.employeeServerId = dto.employeeServerId
                existing.syncStatus = .synced
                existing.updatedAt = Date()
                try context.save()
                return
            }
        }

        let entity = FaceEmbeddingEntity(
            serverId: dto.serverId,
            employeeLocalId: employeeLocalId,
            employeeServerId: dto.employeeServerId,
            pose: FacePose(rawValue: dto.pose) ?? .center,
            encryptedValues: Data(base64Encoded: dto.encryptedValuesBase64) ?? Data(),
            syncStatus: .synced
        )
        try save(entity)
    }
}
