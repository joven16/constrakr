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

    /// Avoid re-downloading the full employee list on every auto-sync tick.
    private var cachedRemoteEmployeeIndex: RemoteEmployeeIndex?
    private var cachedRemoteEmployeeIndexAt: Date?
    private let remoteEmployeeCacheTTL: TimeInterval = 600

    private let uploadConcurrency = 4

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
    func performPushSync(context: ModelContext) async throws -> PushSyncSummary {
        guard NetworkMonitor.shared.isConnected else {
            throw NetworkError.offline
        }

        var summary = PushSyncSummary()

        let empRepo = EmployeeRepository(context: context)
        _ = try empRepo.repairStaleSyncState()

        if AdminSession.shared.isAuthenticated, await api.hasAuthToken() {
            let preCheck = try await EmployeeSyncChecker.check(context: context, repair: true)
            summary.apply(preCheck)
        }

        guard try hasPendingPushWork(context: context) else {
            summary.employeesStillLocalOnly = try empRepo.fetchPendingSync().count
            if summary.employeesLocalTotal == 0 {
                summary.employeesLocalTotal = try empRepo.count()
            }
            return summary
        }

        await api.warmConnection()
        cachedRemoteEmployeeIndex = nil
        cachedRemoteEmployeeIndexAt = nil

        summary = try await uploadPendingEmployees(context: context, summary: summary)
        try await uploadUpdatedEmployees(context: context)
        try await uploadPendingEmbeddings(context: context)
        try await uploadPendingEnrollmentPhotos(context: context)
        try await uploadPendingAttendance(context: context)

        let verify = try await verifyEmployeesOnServer(context: context)
        summary.employeesOnServer = verify.remoteCount
        summary.employeesResetForRetry += verify.resetCount
        summary.employeesStillLocalOnly = try empRepo.fetchPendingSync().count
        let postCheck = try await EmployeeSyncChecker.check(context: context, repair: false)
        summary.apply(postCheck)

        if verify.resetCount > 0 {
            summary = try await uploadPendingEmployees(context: context, summary: summary)
            let secondVerify = try await verifyEmployeesOnServer(context: context)
            summary.employeesOnServer = secondVerify.remoteCount
            summary.employeesStillLocalOnly = try empRepo.fetchPendingSync().count
            let finalCheck = try await EmployeeSyncChecker.check(context: context, repair: false)
            summary.apply(finalCheck)
        }

        if summary.employeesStillLocalOnly > 0 {
            throw NetworkError.serverError(
                statusCode: 0,
                message: summary.failureMessage
            )
        }

        return summary
    }

    struct PushSyncSummary {
        var employeesPosted = 0
        var employeesLinked = 0
        var employeesOnServer = 0
        var employeesStillLocalOnly = 0
        var employeesResetForRetry = 0
        var employeesLocalTotal = 0
        var employeesConfirmedOnIMS = 0

        var successMessage: String {
            if employeesPosted == 0 && employeesLinked == 0 {
                return "\(employeesConfirmedOnIMS)/\(employeesLocalTotal) employees confirmed on IMS (\(employeesOnServer) on server)."
            }
            return "Uploaded \(employeesPosted), linked \(employeesLinked). \(employeesConfirmedOnIMS)/\(employeesLocalTotal) on IMS."
        }

        var failureMessage: String {
            "\(employeesStillLocalOnly) employee(s) still not on IMS. Confirmed: \(employeesConfirmedOnIMS)/\(employeesLocalTotal). Posted: \(employeesPosted)."
        }

        mutating func apply(_ report: EmployeeSyncReport) {
            employeesLocalTotal = report.localTotal
            employeesConfirmedOnIMS = report.confirmedOnIMS
            employeesOnServer = report.remoteTotal
            employeesStillLocalOnly = report.needsUpload
            employeesResetForRetry += report.resetPhantomIds
        }
    }

    private func verifyEmployeesOnServer(context: ModelContext) async throws -> (remoteCount: Int, resetCount: Int) {
        let report = try await EmployeeSyncChecker.check(context: context, repair: true)
        return (report.remoteTotal, report.resetPhantomIds + report.linkedFromServer)
    }

    private func hasPendingPushWork(context: ModelContext) throws -> Bool {
        let employees = EmployeeRepository(context: context)
        let embeddings = FaceEmbeddingRepository(context: context)
        let photos = FaceEnrollmentPhotoRepository(context: context)
        let attendance = AttendanceRepository(context: context)
        return try employees.pendingCount() > 0
            || embeddings.pendingCount() > 0
            || photos.pendingCount() > 0
            || attendance.pendingCount() > 0
    }

    private func persist(_ context: ModelContext) throws {
        try context.save()
    }

    private func uploadPendingEmployees(
        context: ModelContext,
        summary: PushSyncSummary
    ) async throws -> PushSyncSummary {
        var summary = summary
        let repo = EmployeeRepository(context: context)
        let pending = try repo.fetchPendingSync()
        guard !pending.isEmpty else { return summary }

        let remoteIndex = try await remoteEmployeeIndex(forceRefresh: true)

        for employee in pending {
            if let serverId = APIDecoding.normalizedServerId(employee.serverId) {
                employee.serverId = serverId
                employee.syncStatus = .synced
                try repo.update(employee, persist: false)
                continue
            }

            if let remote = remoteIndex.match(for: employee),
               let serverId = APIDecoding.normalizedServerId(remote.serverId) {
                try linkEmployeeToServer(
                    employee,
                    serverId: serverId,
                    context: context,
                    persist: false
                )
                summary.employeesLinked += 1
                continue
            }

            employee.syncStatus = .syncing
            try repo.update(employee, persist: false)

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
                guard let serverId = APIDecoding.normalizedServerId(response.serverId) else {
                    throw NetworkError.serverError(statusCode: 0, message: "Employee POST returned empty server id.")
                }
                try linkEmployeeToServer(
                    employee,
                    serverId: serverId,
                    context: context,
                    persist: false
                )
                summary.employeesPosted += 1
                cachedRemoteEmployeeIndex = nil
                cachedRemoteEmployeeIndexAt = nil
            } catch let error as NetworkError {
                if case .serverError(409, _) = error {
                    let refreshed = try await remoteEmployeeIndex(forceRefresh: true)
                    if let remote = refreshed.match(for: employee),
                       let serverId = APIDecoding.normalizedServerId(remote.serverId) {
                        try linkEmployeeToServer(
                            employee,
                            serverId: serverId,
                            context: context,
                            persist: false
                        )
                        summary.employeesLinked += 1
                        continue
                    }
                }
                employee.syncStatus = .failed
                try? repo.update(employee, persist: false)
                try persist(context)
                throw error
            } catch {
                employee.syncStatus = .failed
                try? repo.update(employee, persist: false)
                try persist(context)
                throw error
            }
        }

        try persist(context)
        return summary
    }

    /// Links a local employee to its server row and propagates `employeeServerId` to child records.
    private func linkEmployeeToServer(
        _ employee: Employee,
        serverId: String,
        context: ModelContext,
        persist: Bool = true
    ) throws {
        let repo = EmployeeRepository(context: context)
        employee.serverId = serverId
        employee.syncStatus = .synced
        try repo.update(employee, persist: false)

        let embRepo = FaceEmbeddingRepository(context: context)
        for emb in try embRepo.fetch(forEmployeeLocalId: employee.id) {
            emb.employeeServerId = serverId
            try embRepo.update(emb, persist: false)
        }

        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        try photoRepo.ensureEntitiesForEmployee(employee)
        for photo in try photoRepo.fetch(forEmployeeLocalId: employee.id) {
            photo.employeeServerId = serverId
            try photoRepo.update(photo, persist: false)
        }

        if persist {
            try self.persist(context)
        }
    }

    private func remoteEmployeeIndex(forceRefresh: Bool) async throws -> RemoteEmployeeIndex {
        if !forceRefresh,
           let cachedRemoteEmployeeIndex,
           let cachedRemoteEmployeeIndexAt,
           Date().timeIntervalSince(cachedRemoteEmployeeIndexAt) < remoteEmployeeCacheTTL {
            return cachedRemoteEmployeeIndex
        }

        let remote = try await api.getEmployees()
        let index = RemoteEmployeeIndex(remote: remote)
        cachedRemoteEmployeeIndex = index
        cachedRemoteEmployeeIndexAt = Date()
        return index
    }

    private func uploadUpdatedEmployees(context: ModelContext) async throws {
        let repo = EmployeeRepository(context: context)
        let pending = try repo.fetchPendingUpdates()
        guard !pending.isEmpty else { return }

        for employee in pending {
            guard let serverId = employee.serverId else { continue }
            employee.syncStatus = .syncing
            try repo.update(employee, persist: false)

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
                try repo.update(employee, persist: false)
            } catch {
                employee.syncStatus = .failed
                try? repo.update(employee, persist: false)
                try persist(context)
                throw error
            }
        }

        try persist(context)
    }

    private func uploadPendingEmbeddings(context: ModelContext) async throws {
        let embRepo = FaceEmbeddingRepository(context: context)
        let empRepo = EmployeeRepository(context: context)
        let pending = try embRepo.fetchPendingSync()
        guard !pending.isEmpty else { return }

        var ready: [FaceEmbeddingEntity] = []
        for entity in pending {
            guard entity.serverId == nil else {
                entity.syncStatus = .synced
                try embRepo.update(entity, persist: false)
                continue
            }

            if entity.employeeServerId == nil,
               let parent = try empRepo.fetch(id: entity.employeeLocalId),
               let serverId = parent.serverId {
                entity.employeeServerId = serverId
            }
            guard entity.employeeServerId != nil else { continue }
            ready.append(entity)
        }

        try await uploadInParallel(items: ready, maxConcurrent: uploadConcurrency) { entity in
            entity.syncStatus = .syncing
            try embRepo.update(entity, persist: false)

            let dto = FaceEmbeddingDTO(
                serverId: nil,
                localId: entity.id,
                employeeServerId: entity.employeeServerId,
                employeeLocalId: entity.employeeLocalId,
                pose: entity.poseRaw,
                encryptedValuesBase64: entity.encryptedValues.base64EncodedString()
            )
            do {
                let response = try await self.api.postFaceEmbedding(dto)
                entity.serverId = response.serverId
                entity.syncStatus = .synced
                try embRepo.update(entity, persist: false)
            } catch {
                entity.syncStatus = .failed
                try? embRepo.update(entity, persist: false)
            }
        }

        try persist(context)
    }

    private func uploadPendingEnrollmentPhotos(context: ModelContext) async throws {
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        let empRepo = EmployeeRepository(context: context)

        let pending = try photoRepo.fetchPendingSync()
        guard !pending.isEmpty else { return }

        let employeeIds = Set(pending.map(\.employeeLocalId))
        for employeeId in employeeIds {
            if let employee = try empRepo.fetch(id: employeeId), employee.serverId != nil {
                try photoRepo.ensureEntitiesForEmployee(employee)
            }
        }

        let refreshedPending = try photoRepo.fetchPendingSync()
        var ready: [FaceEnrollmentPhotoEntity] = []

        for entity in refreshedPending {
            guard entity.serverId == nil else {
                entity.syncStatus = .synced
                try photoRepo.update(entity, persist: false)
                continue
            }

            if entity.employeeServerId == nil,
               let parent = try empRepo.fetch(id: entity.employeeLocalId),
               let serverId = parent.serverId {
                entity.employeeServerId = serverId
            }
            guard entity.employeeServerId != nil else { continue }

            guard EnrollmentPhotoStore.load(
                employeeId: entity.employeeLocalId,
                pose: entity.pose
            ) != nil else {
                continue
            }

            ready.append(entity)
        }

        try await uploadInParallel(items: ready, maxConcurrent: uploadConcurrency) { entity in
            guard let jpeg = EnrollmentPhotoStore.load(
                employeeId: entity.employeeLocalId,
                pose: entity.pose
            ) else { return }

            entity.syncStatus = .syncing
            try photoRepo.update(entity, persist: false)

            let dto = FaceEnrollmentPhotoDTO(
                serverId: nil,
                localId: entity.id,
                employeeServerId: entity.employeeServerId,
                employeeLocalId: entity.employeeLocalId,
                pose: entity.poseRaw,
                jpegBase64: jpeg.base64EncodedString()
            )
            do {
                let response = try await self.api.postFaceEnrollmentPhoto(dto)
                entity.serverId = response.serverId
                entity.syncStatus = .synced
                try photoRepo.update(entity, persist: false)
            } catch {
                entity.syncStatus = .failed
                try? photoRepo.update(entity, persist: false)
            }
        }

        try persist(context)
    }

    private func uploadPendingAttendance(context: ModelContext) async throws {
        let attRepo = AttendanceRepository(context: context)
        let empRepo = EmployeeRepository(context: context)
        let pending = try attRepo.fetchPendingSync()
        guard !pending.isEmpty else { return }

        var ready: [Attendance] = []
        for record in pending {
            guard record.serverId == nil else {
                try attRepo.updateSyncStatus(record, status: .synced, persist: false)
                continue
            }

            if record.employeeServerId == nil,
               let parent = try empRepo.fetch(id: record.employeeId) {
                record.employeeServerId = parent.serverId
            }
            ready.append(record)
        }

        try await uploadInParallel(items: ready, maxConcurrent: uploadConcurrency) { record in
            try attRepo.updateSyncStatus(record, status: .syncing, persist: false)

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
                let response = try await self.api.postAttendance(dto)
                record.serverId = response.serverId
                try attRepo.updateSyncStatus(record, status: .synced, persist: false)
            } catch {
                try? attRepo.updateSyncStatus(record, status: .failed, persist: false)
            }
        }

        try persist(context)
    }

    private func uploadInParallel<T>(
        items: [T],
        maxConcurrent: Int,
        upload: @escaping (T) async throws -> Void
    ) async throws {
        guard !items.isEmpty else { return }

        var index = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            let initial = min(maxConcurrent, items.count)
            for _ in 0..<initial {
                let item = items[index]
                index += 1
                group.addTask { try await upload(item) }
            }

            while let _ = try await group.next() {
                guard index < items.count else { continue }
                let item = items[index]
                index += 1
                group.addTask { try await upload(item) }
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
        let restoreStart = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let remoteAttendance = try await api.getAttendance(
            employeeServerId: nil,
            startDate: restoreStart,
            endDate: Date()
        )
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
