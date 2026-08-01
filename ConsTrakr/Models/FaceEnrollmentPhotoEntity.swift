//
//  FaceEnrollmentPhotoEntity.swift
//  ConsTrakr
//
//  Syncable enrollment JPEG per pose (file bytes live in EnrollmentPhotoStore).
//

import Foundation
import SwiftData

@Model
final class FaceEnrollmentPhotoEntity {
    @Attribute(.unique) var id: UUID
    var serverId: String?
    var employeeLocalId: UUID
    var employeeServerId: String?
    var poseRaw: String
    var syncStatusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        employeeLocalId: UUID,
        employeeServerId: String? = nil,
        pose: FacePose,
        syncStatus: SyncStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverId = serverId
        self.employeeLocalId = employeeLocalId
        self.employeeServerId = employeeServerId
        self.poseRaw = pose.rawValue
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
}
