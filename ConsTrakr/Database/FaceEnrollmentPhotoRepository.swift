//
//  FaceEnrollmentPhotoRepository.swift
//  ConsTrakr
//

import Foundation
import SwiftData

@MainActor
final class FaceEnrollmentPhotoRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetch(forEmployeeLocalId employeeLocalId: UUID) throws -> [FaceEnrollmentPhotoEntity] {
        let descriptor = FetchDescriptor<FaceEnrollmentPhotoEntity>(
            predicate: #Predicate { $0.employeeLocalId == employeeLocalId },
            sortBy: [SortDescriptor(\.poseRaw)]
        )
        return try context.fetch(descriptor)
    }

    func fetchPendingSync() throws -> [FaceEnrollmentPhotoEntity] {
        let pending = SyncStatus.pending.rawValue
        let failed = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<FaceEnrollmentPhotoEntity>(
            predicate: #Predicate { record in
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

    func save(_ entity: FaceEnrollmentPhotoEntity) throws {
        context.insert(entity)
        try context.save()
    }

    func saveAll(_ entities: [FaceEnrollmentPhotoEntity]) throws {
        entities.forEach { context.insert($0) }
        try context.save()
    }

    func update(_ entity: FaceEnrollmentPhotoEntity, persist: Bool = true) throws {
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

    /// Backfill sync rows for JPEGs saved on disk before photo sync existed.
    func ensureEntitiesForEmployee(_ employee: Employee) throws {
        let existing = try fetch(forEmployeeLocalId: employee.id)
        let existingPoses = Set(existing.map(\.poseRaw))
        var toInsert: [FaceEnrollmentPhotoEntity] = []

        for item in EnrollmentPhotoStore.loadAll(employeeId: employee.id) {
            guard !existingPoses.contains(item.pose.rawValue) else { continue }
            toInsert.append(
                FaceEnrollmentPhotoEntity(
                    employeeLocalId: employee.id,
                    employeeServerId: employee.serverId,
                    pose: item.pose,
                    syncStatus: .pending
                )
            )
        }

        if !toInsert.isEmpty {
            try saveAll(toInsert)
        }
    }

    func upsertFromRemote(_ dto: FaceEnrollmentPhotoDTO, employeeLocalId: UUID) throws {
        if let serverId = dto.serverId {
            let descriptor = FetchDescriptor<FaceEnrollmentPhotoEntity>(
                predicate: #Predicate { $0.serverId == serverId }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.poseRaw = dto.pose
                existing.employeeLocalId = employeeLocalId
                existing.employeeServerId = dto.employeeServerId
                existing.syncStatus = .synced
                existing.updatedAt = Date()
                try context.save()
                if let jpegBase64 = dto.jpegBase64,
                   let jpeg = Data(base64Encoded: jpegBase64) {
                    try EnrollmentPhotoStore.saveAll(employeeId: employeeLocalId, photos: [
                        FacePose(rawValue: dto.pose) ?? .center: jpeg
                    ])
                }
                return
            }
        }

        let entity = FaceEnrollmentPhotoEntity(
            serverId: dto.serverId,
            employeeLocalId: employeeLocalId,
            employeeServerId: dto.employeeServerId,
            pose: FacePose(rawValue: dto.pose) ?? .center,
            syncStatus: .synced
        )
        try save(entity)
        if let jpegBase64 = dto.jpegBase64,
           let jpeg = Data(base64Encoded: jpegBase64) {
            try EnrollmentPhotoStore.saveAll(employeeId: employeeLocalId, photos: [
                entity.pose: jpeg
            ])
        }
    }
}
