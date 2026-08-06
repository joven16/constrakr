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
        let syncing = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<FaceEmbeddingEntity>(
            predicate: #Predicate { record in
                (record.syncStatusRaw == pending
                    || record.syncStatusRaw == failed
                    || record.syncStatusRaw == syncing)
                    && record.serverId == nil
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func repairStuckSync() throws -> Int {
        let syncing = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<FaceEmbeddingEntity>(
            predicate: #Predicate { record in
                record.syncStatusRaw == syncing && record.serverId == nil
            }
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

    func save(_ entity: FaceEmbeddingEntity) throws {
        context.insert(entity)
        try context.save()
    }

    func saveAll(_ entities: [FaceEmbeddingEntity]) throws {
        entities.forEach { context.insert($0) }
        try context.save()
    }

    func update(_ entity: FaceEmbeddingEntity, persist: Bool = true) throws {
        entity.updatedAt = Date()
        if persist {
            try context.save()
        }
    }

    func delete(forEmployeeLocalId employeeLocalId: UUID) throws {
        let existing = try fetch(forEmployeeLocalId: employeeLocalId)
        existing.forEach { context.delete($0) }
        try context.save()
    }

    /// Backfill sync rows from the employee's encrypted enrollment blob.
    func ensureEntitiesForEmployee(_ employee: Employee) throws {
        guard employee.isEnrolled else { return }

        let existing = try fetch(forEmployeeLocalId: employee.id)
        let existingPoses = Set(existing.map(\.poseRaw))
        var toInsert: [FaceEmbeddingEntity] = []

        for embedding in employee.faceEmbeddings {
            guard !existingPoses.contains(embedding.pose.rawValue) else { continue }
            let ciphertext = try EmbeddingCrypto.encryptValues(embedding.values)
            toInsert.append(
                FaceEmbeddingEntity(
                    employeeLocalId: employee.id,
                    employeeServerId: employee.serverId,
                    pose: embedding.pose,
                    encryptedValues: ciphertext,
                    syncStatus: .pending
                )
            )
        }

        if !toInsert.isEmpty {
            try saveAll(toInsert)
        }
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
