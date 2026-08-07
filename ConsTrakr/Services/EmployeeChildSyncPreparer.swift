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
        let idDocRepo = EmployeeIdDocumentRepository(context: context)
        let photosOnDisk = !EnrollmentPhotoStore.loadAll(employeeId: employee.id).isEmpty
        let hasIdDocument = IdDocumentPhotoStore.load(employeeId: employee.id) != nil

        if employee.isEnrolled {
            try embRepo.ensureEntitiesForEmployee(employee)
        }
        // Photos live on disk separately — upload even if embedding decrypt fails locally.
        if employee.isEnrolled || photosOnDisk {
            try photoRepo.ensureEntitiesForEmployee(employee)
        }
        if hasIdDocument, let idType = employee.idDocumentType {
            try idDocRepo.ensureEntityForEmployee(
                employee,
                idType: idType,
                idNumber: employee.idDocumentNumber,
                capturedAt: employee.idDocumentCapturedAt
            )
        }

        for emb in try embRepo.fetch(forEmployeeLocalId: employee.id) {
            emb.employeeServerId = serverId
            if emb.serverId == nil, emb.syncStatus == .synced {
                emb.syncStatus = .pending
            }
            try embRepo.update(emb, persist: false)
        }

        for photo in try photoRepo.fetch(forEmployeeLocalId: employee.id) {
            photo.employeeServerId = serverId
            if photo.serverId == nil, photo.syncStatus == .synced {
                photo.syncStatus = .pending
            }
            try photoRepo.update(photo, persist: false)
        }

        if let idDoc = try idDocRepo.fetch(forEmployeeLocalId: employee.id) {
            idDoc.employeeServerId = serverId
            try idDocRepo.update(idDoc, persist: false)
        }

        if persist {
            try context.save()
        }
    }

    static func hasEnrollmentPhotosOnDisk(_ employee: Employee) -> Bool {
        !EnrollmentPhotoStore.loadAll(employeeId: employee.id).isEmpty
    }

    static func shouldUploadPhotos(for employee: Employee) -> Bool {
        employee.serverId != nil && hasEnrollmentPhotosOnDisk(employee)
    }

    static func shouldUploadIdDocument(for employee: Employee) -> Bool {
        employee.serverId != nil && IdDocumentPhotoStore.load(employeeId: employee.id) != nil
    }

    static func shouldUploadEmbeddings(for employee: Employee) -> Bool {
        employee.serverId != nil && employee.isEnrolled
    }
}
