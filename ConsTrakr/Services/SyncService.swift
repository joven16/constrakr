//
//  SyncService.swift
//  ConsTrakr
//
//  CHANGE: Full offline-first orchestrator — push employees, encrypted embeddings,
//  and attendance when online; restore catalog after admin auth on new devices.
//

import Foundation
import SwiftData

@MainActor
final class SyncService {
    private let api: APIService
    private weak var queue: SyncQueue?
    private var context: ModelContext?

    init(api: APIService = .shared, queue: SyncQueue? = nil) {
        self.api = api
        self.queue = queue
    }

    func attach(queue: SyncQueue) {
        self.queue = queue
    }

    func configure(context: ModelContext) {
        self.context = context
        // SyncQueue owns configuration of itself; do not call back into queue.configure.
    }

    func start() {
        queue?.startAutoSync()
    }

    func stop() {
        queue?.stopAutoSync()
    }

    /// Push-only sync used by auto-sync / Sync Now.
    func syncNow() async {
        await queue?.syncNow()
    }

    // MARK: - Push pipeline (called by SyncQueue)

    /// Uploads pending local changes in dependency order.
    /// INTEGRATION: Each step maps 1:1 to the placeholder REST endpoints.
    func performPushSync(context: ModelContext) async throws {
        guard NetworkMonitor.shared.isConnected else {
            throw NetworkError.offline
        }

        try await uploadPendingEmployees(context: context)
        try await uploadUpdatedEmployees(context: context)
        try await uploadPendingEmbeddings(context: context)
        try await uploadPendingEnrollmentPhotos(context: context)
        try await uploadPendingAttendance(context: context)
    }

    private func uploadPendingEmployees(context: ModelContext) async throws {
        let repo = EmployeeRepository(context: context)
        let pending = try repo.fetchPendingSync()
        for employee in pending {
            // Duplicate prevention: skip anything that already has a serverId.
            guard employee.serverId == nil else {
                employee.syncStatus = .synced
                try repo.update(employee)
                continue
            }
            employee.syncStatus = .syncing
            try repo.update(employee)

            let dto = EmployeeDTO(
                serverId: nil,
                localId: employee.id,
                employeeCode: employee.employeeCode,
                firstName: employee.firstName,
                lastName: employee.lastName,
                department: employee.department,
                encryptedDepthSignatureBase64: employee.faceDepthSignatureData.isEmpty
                    ? nil
                    : employee.faceDepthSignatureData.base64EncodedString()
            )
            do {
                let response = try await api.postEmployee(dto)
                employee.serverId = response.serverId
                employee.syncStatus = .synced
                try repo.update(employee)

                // Propagate employeeServerId onto pending embedding rows.
                let embRepo = FaceEmbeddingRepository(context: context)
                for emb in try embRepo.fetch(forEmployeeLocalId: employee.id) {
                    emb.employeeServerId = response.serverId
                    try embRepo.update(emb)
                }

                let photoRepo = FaceEnrollmentPhotoRepository(context: context)
                try photoRepo.ensureEntitiesForEmployee(employee)
                for photo in try photoRepo.fetch(forEmployeeLocalId: employee.id) {
                    photo.employeeServerId = response.serverId
                    try photoRepo.update(photo)
                }
            } catch {
                employee.syncStatus = .failed
                try? repo.update(employee)
                throw error
            }
        }
    }

    private func uploadUpdatedEmployees(context: ModelContext) async throws {
        let repo = EmployeeRepository(context: context)
        let pending = try repo.fetchPendingUpdates()

        for employee in pending {
            guard let serverId = employee.serverId else { continue }
            employee.syncStatus = .syncing
            try repo.update(employee)

            let dto = EmployeeDTO(
                serverId: serverId,
                localId: employee.id,
                employeeCode: employee.employeeCode,
                firstName: employee.firstName,
                lastName: employee.lastName,
                department: employee.department,
                encryptedDepthSignatureBase64: employee.faceDepthSignatureData.isEmpty
                    ? nil
                    : employee.faceDepthSignatureData.base64EncodedString()
            )
            do {
                _ = try await api.putEmployee(dto)
                employee.syncStatus = .synced
                try repo.update(employee)
            } catch {
                employee.syncStatus = .failed
                try? repo.update(employee)
                throw error
            }
        }
    }

    private func uploadPendingEmbeddings(context: ModelContext) async throws {
        let embRepo = FaceEmbeddingRepository(context: context)
        let empRepo = EmployeeRepository(context: context)
        let pending = try embRepo.fetchPendingSync()

        for entity in pending {
            guard entity.serverId == nil else {
                entity.syncStatus = .synced
                try embRepo.update(entity)
                continue
            }

            // Wait until parent employee is synced so the backend can link embeddings.
            if entity.employeeServerId == nil,
               let parent = try empRepo.fetch(id: entity.employeeLocalId),
               let serverId = parent.serverId {
                entity.employeeServerId = serverId
            }
            guard entity.employeeServerId != nil else { continue }

            entity.syncStatus = .syncing
            try embRepo.update(entity)

            let dto = FaceEmbeddingDTO(
                serverId: nil,
                localId: entity.id,
                employeeServerId: entity.employeeServerId,
                employeeLocalId: entity.employeeLocalId,
                pose: entity.poseRaw,
                encryptedValuesBase64: entity.encryptedValues.base64EncodedString()
            )
            do {
                let response = try await api.postFaceEmbedding(dto)
                entity.serverId = response.serverId
                entity.syncStatus = .synced
                try embRepo.update(entity)
            } catch {
                entity.syncStatus = .failed
                try? embRepo.update(entity)
                throw error
            }
        }
    }

    private func uploadPendingEnrollmentPhotos(context: ModelContext) async throws {
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        let empRepo = EmployeeRepository(context: context)

        // Backfill sync rows for employees registered before photo sync shipped.
        for employee in try empRepo.fetchAll() where employee.serverId != nil {
            try photoRepo.ensureEntitiesForEmployee(employee)
        }

        let pending = try photoRepo.fetchPendingSync()
        for entity in pending {
            guard entity.serverId == nil else {
                entity.syncStatus = .synced
                try photoRepo.update(entity)
                continue
            }

            if entity.employeeServerId == nil,
               let parent = try empRepo.fetch(id: entity.employeeLocalId),
               let serverId = parent.serverId {
                entity.employeeServerId = serverId
            }
            guard entity.employeeServerId != nil else { continue }

            guard let jpeg = EnrollmentPhotoStore.load(
                employeeId: entity.employeeLocalId,
                pose: entity.pose
            ) else {
                continue
            }

            entity.syncStatus = .syncing
            try photoRepo.update(entity)

            let dto = FaceEnrollmentPhotoDTO(
                serverId: nil,
                localId: entity.id,
                employeeServerId: entity.employeeServerId,
                employeeLocalId: entity.employeeLocalId,
                pose: entity.poseRaw,
                jpegBase64: jpeg.base64EncodedString()
            )
            do {
                let response = try await api.postFaceEnrollmentPhoto(dto)
                entity.serverId = response.serverId
                entity.syncStatus = .synced
                try photoRepo.update(entity)
            } catch {
                entity.syncStatus = .failed
                try? photoRepo.update(entity)
                throw error
            }
        }
    }

    private func uploadPendingAttendance(context: ModelContext) async throws {
        let attRepo = AttendanceRepository(context: context)
        let empRepo = EmployeeRepository(context: context)
        let pending = try attRepo.fetchPendingSync()

        for record in pending {
            guard record.serverId == nil else {
                try attRepo.updateSyncStatus(record, status: .synced)
                continue
            }

            if record.employeeServerId == nil,
               let parent = try empRepo.fetch(id: record.employeeId) {
                record.employeeServerId = parent.serverId
            }

            try attRepo.updateSyncStatus(record, status: .syncing)

            let punchJPEG = AttendancePhotoStore.load(attendanceId: record.id)
            let dto = AttendanceDTO(
                serverId: nil,
                localId: record.id,
                employeeServerId: record.employeeServerId,
                employeeLocalId: record.employeeId,
                checkType: record.checkTypeRaw,
                timestamp: record.timestamp,
                confidenceScore: record.confidenceScore,
                notes: record.notes,
                punchPhotoBase64: punchJPEG?.base64EncodedString()
            )
            do {
                let response = try await api.postAttendance(dto)
                record.serverId = response.serverId
                try attRepo.updateSyncStatus(record, status: .synced)
            } catch {
                try? attRepo.updateSyncStatus(record, status: .failed)
                throw error
            }
        }
    }

    // MARK: - Restore (new device)

    /// Downloads employees + encrypted embeddings after admin authentication.
    /// App remains fully offline-capable after this completes.
    func restoreFromServer(context: ModelContext) async throws -> RestoreSummary {
        guard NetworkMonitor.shared.isConnected else { throw NetworkError.offline }

        let empRepo = EmployeeRepository(context: context)
        let embRepo = FaceEmbeddingRepository(context: context)
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)

        // INTEGRATION: GET /employees
        let remoteEmployees = try await api.getEmployees()
        var employeeCount = 0
        var localIdByServerId: [String: UUID] = [:]

        for dto in remoteEmployees {
            let employee = try empRepo.upsertFromRemote(dto)
            employeeCount += 1
            if let serverId = employee.serverId {
                localIdByServerId[serverId] = employee.id
            }
        }

        // INTEGRATION: GET /face-embeddings (encrypted only)
        let remoteEmbeddings = try await api.getFaceEmbeddings()
        var embeddingCount = 0

        for dto in remoteEmbeddings {
            let localEmployeeId: UUID
            if let serverId = dto.employeeServerId, let mapped = localIdByServerId[serverId] {
                localEmployeeId = mapped
            } else if let existing = try empRepo.fetch(id: dto.employeeLocalId) {
                localEmployeeId = existing.id
            } else {
                continue
            }

            try embRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
            embeddingCount += 1

            // Rebuild Employee.faceEmbeddingsData from decrypted entities for offline matching.
            if let employee = try empRepo.fetch(id: localEmployeeId) {
                let entities = try embRepo.fetch(forEmployeeLocalId: localEmployeeId)
                let embeddings = entities.compactMap { try? $0.decryptedEmbedding() }
                employee.faceEmbeddings = embeddings
                employee.syncStatus = .synced
                try empRepo.update(employee)
            }
        }

        // INTEGRATION: GET /face-enrollment-photos
        let remotePhotos = try await api.getFaceEnrollmentPhotos()
        var photoCount = 0
        for dto in remotePhotos {
            let localEmployeeId: UUID
            if let serverId = dto.employeeServerId, let mapped = localIdByServerId[serverId] {
                localEmployeeId = mapped
            } else if let existing = try empRepo.fetch(id: dto.employeeLocalId) {
                localEmployeeId = existing.id
            } else {
                continue
            }
            try photoRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
            photoCount += 1
        }

        // Optional: GET /attendance for history restore (does not block offline recognition).
        let remoteAttendance = try await api.getAttendance()
        var attendanceCount = 0
        for dto in remoteAttendance {
            let already = try attExists(context: context, serverId: dto.serverId, localId: dto.localId)
            guard !already else { continue }
            let record = Attendance(
                id: dto.localId,
                serverId: dto.serverId,
                employeeId: dto.employeeLocalId,
                employeeServerId: dto.employeeServerId,
                checkType: CheckType(rawValue: dto.checkType) ?? .checkIn,
                timestamp: dto.timestamp,
                syncStatus: .synced,
                confidenceScore: dto.confidenceScore,
                notes: dto.notes
            )
            context.insert(record)
            if let punchBase64 = dto.punchPhotoBase64,
               let jpeg = Data(base64Encoded: punchBase64) {
                try? AttendancePhotoStore.save(attendanceId: record.id, jpeg: jpeg)
            }
            attendanceCount += 1
        }
        try context.save()

        return RestoreSummary(
            employees: employeeCount,
            embeddings: embeddingCount,
            enrollmentPhotos: photoCount,
            attendance: attendanceCount
        )
    }

    private func attExists(context: ModelContext, serverId: String?, localId: UUID) throws -> Bool {
        if let serverId {
            let descriptor = FetchDescriptor<Attendance>(predicate: #Predicate { $0.serverId == serverId })
            if try context.fetchCount(descriptor) > 0 { return true }
        }
        let byLocal = FetchDescriptor<Attendance>(predicate: #Predicate { $0.id == localId })
        return try context.fetchCount(byLocal) > 0
    }

    struct RestoreSummary {
        let employees: Int
        let embeddings: Int
        let enrollmentPhotos: Int
        let attendance: Int
    }
}
