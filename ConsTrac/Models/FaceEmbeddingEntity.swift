//
//  FaceEmbeddingEntity.swift
//  ConsTrac
//
//  CHANGE: Separate SwiftData entity for syncable encrypted embeddings.
//  Local `id` is never assumed to equal `serverId`.
//

import Foundation
import SwiftData

@Model
final class FaceEmbeddingEntity {
    @Attribute(.unique) var id: UUID
    /// Backend identifier after POST /face-embeddings — nil until synced.
    var serverId: String?
    var employeeLocalId: UUID
    /// Set after the parent employee has a serverId (needed for upload payloads).
    var employeeServerId: String?
    var poseRaw: String
    /// AES-GCM ciphertext of the Float vector — never store plaintext floats here.
    var encryptedValues: Data
    var syncStatusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        employeeLocalId: UUID,
        employeeServerId: String? = nil,
        pose: FacePose,
        encryptedValues: Data,
        syncStatus: SyncStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverId = serverId
        self.employeeLocalId = employeeLocalId
        self.employeeServerId = employeeServerId
        self.poseRaw = pose.rawValue
        self.encryptedValues = encryptedValues
        self.syncStatusRaw = syncStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var pose: FacePose {
        get { FacePose(rawValue: poseRaw) ?? .center }
        set { poseRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// Decrypt for local matching only — do not upload this plaintext.
    func decryptedEmbedding() throws -> FaceEmbedding {
        let values = try EmbeddingCrypto.decryptValues(encryptedValues)
        return FaceEmbedding(pose: pose, values: values, capturedAt: createdAt)
    }
}
