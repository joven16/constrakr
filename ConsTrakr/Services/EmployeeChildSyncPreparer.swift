//
//  EmployeeChildSyncPreparer.swift
//  ConsTrakr
//
//  Ensures face embedding / enrollment photo sync rows exist and are linked
//  to the parent employee's IMS id before upload.
//

import Foundation
import SwiftData

@MainActor
enum EmployeeChildSyncPreparer {
    /// Backfill and relink child sync records for every employee already on IMS.
    static func prepareAll(context: ModelContext, persist: Bool = true) throws {
        let empRepo = EmployeeRepository(context: context)
        for employee in try empRepo.fetchAll() {
            do {
                try prepare(for: employee, context: context, persist: false)
            } catch {
                // One bad enrollment must not block sync for everyone else.
                continue
            }
        }
        if persist {
            try context.save()
        }
    }

    static func prepare(for employee: Employee, context: ModelContext, persist: Bool = false) throws {
        guard let serverId = APIDecoding.normalizedServerId(employee.serverId) else { return }
        employee.serverId = serverId

        let embRepo = FaceEmbeddingRepository(context: context)
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)

        if employee.isEnrolled {
            try embRepo.ensureEntitiesForEmployee(employee)
            try photoRepo.ensureEntitiesForEmployee(employee)
        }

        for emb in try embRepo.fetch(forEmployeeLocalId: employee.id) {
            if emb.employeeServerId != serverId {
                emb.employeeServerId = serverId
            }
            if emb.serverId == nil, emb.syncStatus == .synced {
                emb.syncStatus = .pending
            }
            try embRepo.update(emb, persist: false)
        }

        for photo in try photoRepo.fetch(forEmployeeLocalId: employee.id) {
            if photo.employeeServerId != serverId {
                photo.employeeServerId = serverId
            }
            if photo.serverId == nil, photo.syncStatus == .synced {
                photo.syncStatus = .pending
            }
            try photoRepo.update(photo, persist: false)
        }

        if persist {
            try context.save()
        }
    }
}
