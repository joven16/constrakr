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
    private let warmConnectionTTL: TimeInterval = 300
    private let photoReconcileTTL: TimeInterval = 1800

    private var lastWarmConnectionAt: Date?
    private var lastChildAssetsReconcileAt: Date?

    private let uploadConcurrency = 6

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
    func performPushSync(
        context: ModelContext,
        mode: SyncMode = .full,
        scope: SyncScope = .all,
        dtrFocusDate: Date? = nil
    ) async throws -> PushSyncSummary {
        guard NetworkMonitor.shared.isConnected else {
            throw NetworkError.offline
        }

        if scope == .attendance {
            return try await performAttendanceOnlySync(context: context, dtrFocusDate: dtrFocusDate)
        }

        var summary = PushSyncSummary()
        let empRepo = EmployeeRepository(context: context)
        _ = try empRepo.repairStaleSyncState()

        reportProgress("Syncing job sites…")
        async let jobSitesTask = syncJobSites(context: context)
        async let departmentsTask = syncDepartments()
        await processPendingEmployeeDeletions()
        await warmConnectionIfNeeded()

        reportProgress(mode == .quick ? "Checking updates…" : "Downloading roster…")
        async let rosterTask: RemoteRosterFetch = fetchRemoteRoster(mode: mode)
        summary.jobSitesSynced = try await jobSitesTask
        _ = try await departmentsTask
        let rosterResult = try await rosterTask
        var remoteEmployees = rosterResult.employees
        var remoteParsed = rosterResult.parsed

        reportProgress("Applying server changes…")
        summary.employeesImportedFromIMS = try await importMissingRemoteEmployees(
            context: context,
            remoteEmployees: remoteEmployees
        )
        if summary.employeesImportedFromIMS > 0 {
            let refreshed = try await fetchRemoteRoster(mode: .full)
            remoteEmployees = refreshed.employees
            remoteParsed = refreshed.parsed
        }

        summary.profilesMergedFromIMS = try await mergeRemoteEmployeeProfileUpdates(
            context: context,
            remoteEmployees: remoteEmployees
        )
        try await uploadUpdatedEmployees(context: context)
        try await pushChangedJobSiteAssignments(
            context: context,
            remoteEmployees: remoteEmployees
        )

        if try shouldPrepareChildRows(context: context, mode: mode) {
            do {
                try EmployeeChildSyncPreparer.prepareAll(context: context, persist: true)
            } catch {
                // Non-fatal — upload steps also prepare per employee.
            }
        }
        _ = try FaceEmbeddingRepository(context: context).repairStuckSync()
        _ = try FaceEnrollmentPhotoRepository(context: context).repairStuckSync()
        _ = try EmployeeIdDocumentRepository(context: context).repairStuckSync()

        if shouldReconcileRemoteChildAssets(context: context, mode: mode) {
            reportProgress("Verifying photos & ID documents…")
            try await reconcileRemoteChildAssets(context: context)
            lastChildAssetsReconcileAt = Date()
        }

        guard try hasPendingPushWork(context: context, scope: scope) else {
            if scope != .employees {
                reportProgress("Checking server updates…")
                try await reconcileRemoteAttendanceVoids(context: context)
                try await pullRemoteAttendance(context: context, focusDate: dtrFocusDate)
            }
            reportProgress("Verifying roster…")
            summary.employeesStillLocalOnly = try empRepo.fetchPendingSync().count
            summary.employeesLocalTotal = try empRepo.count()
            let report = try await EmployeeSyncChecker.check(
                context: context,
                repair: false,
                preloadedParsed: remoteParsed
            )
            summary.apply(report)
            summary.employeeSyncReport = report
            reportProgress(nil)
            return summary
        }

        reportProgress("Uploading employees…")
        summary = try await uploadPendingEmployees(context: context, summary: summary)
        try await uploadUpdatedEmployees(context: context)
        try await pushChangedJobSiteAssignments(
            context: context,
            remoteEmployees: remoteEmployees
        )
        reportProgress("Uploading face data…")
        summary = try await uploadPendingEmbeddings(context: context, summary: summary)
        summary = try await uploadPendingEnrollmentPhotos(context: context, summary: summary)
        summary = try await uploadPendingIdDocuments(context: context, summary: summary)
        if scope != .employees {
            reportProgress("Uploading attendance…")
            try await uploadPendingAttendance(context: context)
            reportProgress("Checking server updates…")
            try await reconcileRemoteAttendanceVoids(context: context)
            try await pullRemoteAttendance(context: context, focusDate: dtrFocusDate)
        }

        if summary.employeesPosted > 0
            || summary.employeesLinked > 0
            || summary.profilesMergedFromIMS > 0
            || summary.embeddingsUploaded > 0
            || summary.photosUploaded > 0
            || summary.idDocumentsUploaded > 0 {
            let refreshed = try await fetchRemoteRoster(mode: .full)
            remoteEmployees = refreshed.employees
            remoteParsed = refreshed.parsed
        }

        reportProgress("Verifying roster…")
        let report = try await EmployeeSyncChecker.check(
            context: context,
            repair: mode == .full,
            preloadedParsed: remoteParsed
        )
        summary.apply(report)
        summary.employeeSyncReport = report
        summary.employeesOnServer = report.remoteTotal
        summary.employeesResetForRetry += report.resetPhantomIds + report.linkedFromServer
        summary.employeesStillLocalOnly = try empRepo.fetchPendingSync().count

        if report.resetPhantomIds + report.linkedFromServer > 0,
           summary.employeesStillLocalOnly > 0 {
            summary = try await uploadPendingEmployees(context: context, summary: summary)
            summary.employeesStillLocalOnly = try empRepo.fetchPendingSync().count
        }

        reportProgress(nil)
        return summary
    }

    private func performAttendanceOnlySync(
        context: ModelContext,
        dtrFocusDate: Date? = nil
    ) async throws -> PushSyncSummary {
        await warmConnectionIfNeeded()
        reportProgress("Uploading punches…")
        try await uploadPendingAttendance(context: context)
        reportProgress("Checking server updates…")
        try await reconcileRemoteAttendanceVoids(context: context)
        reportProgress("Downloading server DTR…")
        try await pullRemoteAttendance(context: context, focusDate: dtrFocusDate)
        reportProgress(nil)
        return PushSyncSummary()
    }

    /// Imports IMS punches for the DTR day (including manual corrections) and prunes replaced rows.
    private func pullRemoteAttendance(context: ModelContext, focusDate: Date?) async throws {
        let calendar = Calendar.current
        let rangeStart: Date
        let rangeEnd: Date
        if let focusDate {
            rangeStart = calendar.startOfDay(for: focusDate)
            rangeEnd = rangeStart
        } else if let recent = calendar.date(byAdding: .day, value: -14, to: Date()) {
            rangeStart = calendar.startOfDay(for: recent)
            rangeEnd = calendar.startOfDay(for: Date())
        } else {
            return
        }

        let remoteRows = try await api.getAttendance(
            employeeServerId: nil,
            startDate: rangeStart,
            endDate: rangeEnd,
            includeMedia: false
        )
        let activeRows = remoteRows.filter { !$0.isVoid }
        guard !activeRows.isEmpty || focusDate != nil else { return }

        let empRepo = EmployeeRepository(context: context)
        let attRepo = AttendanceRepository(context: context)
        var localIdByServerId: [String: UUID] = [:]
        for employee in try empRepo.fetchAll() {
            if let serverId = APIDecoding.normalizedServerId(employee.serverId) {
                localIdByServerId[serverId] = employee.id
            }
        }

        var changed = false

        if let focusDate {
            let dayStart = calendar.startOfDay(for: focusDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?
                .addingTimeInterval(-0.001) ?? dayStart
            let remoteServerIds = Set(
                activeRows.compactMap { APIDecoding.normalizedServerId($0.serverId) }
            )
            let localDayRecords = try attRepo.fetchAll(from: dayStart, to: dayEnd)
            for local in localDayRecords {
                guard let serverId = APIDecoding.normalizedServerId(local.serverId) else { continue }
                if !remoteServerIds.contains(serverId) {
                    try attRepo.delete(local, persist: false)
                    changed = true
                }
            }
        }

        for dto in activeRows {
            guard let localEmployeeId = try resolveRestoreEmployeeId(
                dtoEmployeeServerId: dto.employeeServerId,
                dtoEmployeeLocalId: dto.employeeLocalId,
                localIdByServerId: localIdByServerId,
                empRepo: empRepo
            ) else { continue }

            let normalizedServerId = APIDecoding.normalizedServerId(dto.serverId)
            if let normalizedServerId,
               let existing = try attRepo.fetch(serverId: normalizedServerId) {
                if existing.timestamp != dto.timestamp || existing.notes != dto.notes {
                    existing.timestamp = dto.timestamp
                    existing.notes = dto.notes
                    changed = true
                }
                continue
            }

            if let existing = try attRepo.fetch(localId: dto.localId) {
                if existing.serverId == nil, let normalizedServerId {
                    existing.serverId = normalizedServerId
                    existing.syncStatus = .synced
                    changed = true
                }
                continue
            }

            let record = Attendance(
                id: dto.localId,
                serverId: normalizedServerId,
                employeeId: localEmployeeId,
                employeeServerId: dto.employeeServerId,
                checkType: CheckType(rawValue: dto.checkType) ?? .checkIn,
                timestamp: dto.timestamp,
                syncStatus: .synced,
                confidenceScore: dto.confidenceScore,
                notes: dto.notes
            )
            context.insert(record)
            changed = true
        }

        if changed {
            try persist(context)
            NotificationCenter.default.post(name: AppConstants.Notifications.attendanceDidChange, object: nil)
        }
    }

    /// Removes local punches voided on IMS so DTR and scanner stay aligned.
    private func reconcileRemoteAttendanceVoids(context: ModelContext) async throws {
        let attRepo = AttendanceRepository(context: context)
        // Use a wide lookback so voids are found even when IMS `updated_at` was not bumped on older builds.
        guard let since = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return }

        let remoteRows = try await api.getAttendance(updatedSince: since)
        let voidedRows = remoteRows.filter(\.isVoid)
        guard !voidedRows.isEmpty else {
            SyncSettings.recordAttendanceVoidReconcile()
            return
        }

        var removed = 0
        for dto in voidedRows {
            guard let local = try attRepo.fetchForVoidReconcile(
                serverId: APIDecoding.normalizedServerId(dto.serverId),
                localId: dto.localId,
                employeeServerId: APIDecoding.normalizedServerId(dto.employeeServerId),
                timestamp: dto.timestamp,
                checkType: dto.checkType
            ) else { continue }
            try attRepo.delete(local, persist: false)
            removed += 1
        }

        if removed > 0 {
            try persist(context)
            NotificationCenter.default.post(name: AppConstants.Notifications.attendanceDidChange, object: nil)
        }
        SyncSettings.recordAttendanceVoidReconcile()
    }

    private func reportProgress(_ message: String?) {
        queue?.updateSyncProgress(message)
    }

    private struct RemoteRosterFetch {
        let employees: [EmployeeDTO]
        let parsed: APIDecoding.EmployeeListDecodeResult
    }

    private func fetchRemoteRoster(mode: SyncMode) async throws -> RemoteRosterFetch {
        switch mode {
        case .full:
            let remote = try await api.getEmployees()
            SyncSettings.recordFullRosterSync()
            cacheRemoteEmployees(remote)
            let parsed = APIDecoding.EmployeeListDecodeResult(
                employees: remote,
                rawCount: remote.count
            )
            return RemoteRosterFetch(employees: remote, parsed: parsed)

        case .quick:
            if let since = SyncSettings.lastFullRosterSyncDate,
               let cached = cachedRemoteEmployeeIndex,
               let cachedAt = cachedRemoteEmployeeIndexAt,
               Date().timeIntervalSince(cachedAt) < remoteEmployeeCacheTTL {
                let delta = try await api.getEmployees(updatedSince: since.addingTimeInterval(-120))
                if delta.isEmpty {
                    let employees = cached.allEmployees
                    let parsed = APIDecoding.EmployeeListDecodeResult(
                        employees: employees,
                        rawCount: employees.count
                    )
                    return RemoteRosterFetch(employees: employees, parsed: parsed)
                }
                var index = cached
                for dto in delta {
                    index.insert(dto)
                }
                cachedRemoteEmployeeIndex = index
                cachedRemoteEmployeeIndexAt = Date()
                let merged = index.allEmployees
                let parsed = APIDecoding.EmployeeListDecodeResult(
                    employees: merged,
                    rawCount: merged.count
                )
                return RemoteRosterFetch(employees: merged, parsed: parsed)
            }

            let remote = try await api.getEmployees()
            SyncSettings.recordFullRosterSync()
            cacheRemoteEmployees(remote)
            let parsed = APIDecoding.EmployeeListDecodeResult(
                employees: remote,
                rawCount: remote.count
            )
            return RemoteRosterFetch(employees: remote, parsed: parsed)
        }
    }

    private func shouldPrepareChildRows(context: ModelContext, mode: SyncMode) throws -> Bool {
        if mode == .full { return true }
        let embeddings = FaceEmbeddingRepository(context: context)
        let photos = FaceEnrollmentPhotoRepository(context: context)
        let idDocuments = EmployeeIdDocumentRepository(context: context)
        let employees = EmployeeRepository(context: context)
        return try employees.pendingCount() > 0
            || embeddings.pendingCount() > 0
            || photos.pendingCount() > 0
            || idDocuments.pendingCount() > 0
    }

    private func shouldUploadLargeMedia() -> Bool {
        guard SyncSettings.uploadLargeFilesOnWiFiOnly else { return true }
        return NetworkMonitor.shared.isOnWiFi
    }

    private func warmConnectionIfNeeded() async {
        if let lastWarmConnectionAt,
           Date().timeIntervalSince(lastWarmConnectionAt) < warmConnectionTTL {
            return
        }
        await api.warmConnection()
        lastWarmConnectionAt = Date()
    }

    private func cacheRemoteEmployees(_ remote: [EmployeeDTO]) {
        let index = RemoteEmployeeIndex(remote: remote)
        cachedRemoteEmployeeIndex = index
        cachedRemoteEmployeeIndexAt = Date()
    }

    private func shouldReconcileRemoteChildAssets(context: ModelContext, mode: SyncMode) -> Bool {
        let photoPending = (try? FaceEnrollmentPhotoRepository(context: context).pendingCount()) ?? 0
        let idDocPending = (try? EmployeeIdDocumentRepository(context: context).pendingCount()) ?? 0
        if photoPending > 0 || idDocPending > 0 { return true }
        if mode == .quick { return false }
        guard let lastChildAssetsReconcileAt else { return true }
        return Date().timeIntervalSince(lastChildAssetsReconcileAt) >= photoReconcileTTL
    }

    struct PushSyncSummary {
        var jobSitesSynced = 0
        var employeesPosted = 0
        var employeesLinked = 0
        var employeesImportedFromIMS = 0
        var profilesMergedFromIMS = 0
        var employeesOnServer = 0
        var employeesStillLocalOnly = 0
        var employeesResetForRetry = 0
        var employeesLocalTotal = 0
        var employeesConfirmedOnIMS = 0
        var embeddingsUploaded = 0
        var embeddingsFailed = 0
        var photosUploaded = 0
        var photosFailed = 0
        var photosSkippedNoFile = 0
        var idDocumentsUploaded = 0
        var idDocumentsFailed = 0
        var idDocumentsSkippedNoFile = 0
        var employeesUploadFailed = 0
        var lastUploadError: String?
        var lastPhotoUploadError: String?
        var lastIdDocumentUploadError: String?
        var employeeSyncReport: EmployeeSyncReport?

        var successMessage: String {
            if employeesPosted == 0 && employeesLinked == 0 {
                var parts = ["\(employeesConfirmedOnIMS)/\(employeesLocalTotal) employees on server"]
                if employeesImportedFromIMS > 0 {
                    parts.append("\(employeesImportedFromIMS) imported from server")
                }
                if embeddingsUploaded > 0 || photosUploaded > 0 {
                    parts.append("\(embeddingsUploaded) embeddings, \(photosUploaded) photos uploaded")
                }
                return parts.joined(separator: " · ")
            }
            return "Uploaded \(employeesPosted), linked \(employeesLinked). \(employeesConfirmedOnIMS)/\(employeesLocalTotal) on server."
        }

        var failureMessage: String {
            var parts: [String] = []
            if employeesStillLocalOnly > 0 {
                parts.append("\(employeesStillLocalOnly) employee(s) still not on server")
            }
            if employeesUploadFailed > 0 {
                parts.append("\(employeesUploadFailed) employee upload(s) failed")
            }
            if embeddingsFailed > 0 {
                parts.append("\(embeddingsFailed) embedding(s) failed to upload")
            }
            if photosFailed > 0 {
                parts.append("\(photosFailed) photo(s) failed to upload")
            }
            if photosSkippedNoFile > 0 {
                parts.append("\(photosSkippedNoFile) photo(s) missing on device")
            }
            if let lastPhotoUploadError, photosFailed > 0 {
                parts.append(lastPhotoUploadError)
            }
            if parts.isEmpty {
                return lastUploadError ?? "Sync finished with issues. Tap Sync Now to retry."
            }
            if let lastUploadError, !parts.contains(where: { $0.contains(lastUploadError) }) {
                return parts.joined(separator: ". ") + ". " + lastUploadError
            }
            return parts.joined(separator: ". ") + "."
        }

        var hasChildUploadIssues: Bool {
            embeddingsFailed > 0 || photosFailed > 0 || photosSkippedNoFile > 0 || employeesUploadFailed > 0
        }

        mutating func apply(_ report: EmployeeSyncReport) {
            employeesLocalTotal = report.localTotal
            employeesConfirmedOnIMS = report.confirmedOnIMS
            employeesOnServer = report.remoteTotal
            employeesStillLocalOnly = report.needsUpload
            employeesResetForRetry += report.resetPhantomIds
        }
    }

    private func hasPendingPushWork(context: ModelContext, scope: SyncScope) throws -> Bool {
        if scope == .attendance {
            return try AttendanceRepository(context: context).pendingCount() > 0
        }

        if PendingEmployeeDeletionStore.hasPending() {
            return true
        }
        if JobSiteStore.hasPendingSync {
            return true
        }
        let employees = EmployeeRepository(context: context)
        let embeddings = FaceEmbeddingRepository(context: context)
        let photos = FaceEnrollmentPhotoRepository(context: context)
        let idDocuments = EmployeeIdDocumentRepository(context: context)
        let employeePending = try employees.pendingCount()
        let embeddingPending = try embeddings.pendingCount()
        let photoPending = try photos.pendingCount()
        let idDocPending = try idDocuments.pendingCount()
        let hasEmployeeWork = employeePending > 0
            || embeddingPending > 0
            || photoPending > 0
            || idDocPending > 0
        if scope == .employees {
            return hasEmployeeWork
        }
        let attendancePending = try AttendanceRepository(context: context).pendingCount()
        return hasEmployeeWork || attendancePending > 0
    }

    /// Soft-delete employees on IMS that were removed on this device.
    func processPendingEmployeeDeletions() async {
        let pending = PendingEmployeeDeletionStore.pendingServerIds()
        guard !pending.isEmpty else { return }
        guard NetworkMonitor.shared.isConnected else { return }
        guard AdminSession.shared.isAuthenticated else { return }
        guard await api.hasAuthToken() else { return }

        for serverId in pending {
            do {
                try await api.deleteEmployee(serverId: serverId)
                PendingEmployeeDeletionStore.remove(serverId: serverId)
            } catch let error as NetworkError {
                switch error {
                case .serverError(404, _):
                    PendingEmployeeDeletionStore.remove(serverId: serverId)
                default:
                    break
                }
            } catch {
                break
            }
        }
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

        let remoteIndex = try await remoteEmployeeIndex(forceRefresh: false)

        for employee in pending {
            if let serverId = APIDecoding.normalizedServerId(employee.serverId) {
                try linkEmployeeToServer(
                    employee,
                    serverId: serverId,
                    context: context,
                    persist: false
                )
                continue
            }

            if remoteIndex.match(for: employee) != nil,
               let serverId = remoteIndex.resolvedServerId(for: employee) {
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

            let dto = EmployeeDTO.fromLocalEmployee(employee, serverId: nil)
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
                    if refreshed.match(for: employee) != nil,
                       let serverId = refreshed.resolvedServerId(for: employee) {
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
                summary.employeesUploadFailed += 1
                summary.lastUploadError = error.localizedDescription
            } catch {
                employee.syncStatus = .failed
                try? repo.update(employee, persist: false)
                summary.employeesUploadFailed += 1
                summary.lastUploadError = error.localizedDescription
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

            let dto = EmployeeDTO.fromLocalEmployee(employee, serverId: serverId)
            do {
                _ = try await api.putEmployee(dto)
                employee.syncStatus = .synced
                try repo.update(employee, persist: false)
            } catch {
                employee.syncStatus = .failed
                try? repo.update(employee, persist: false)
            }
        }

        try persist(context)
    }

    /// Keeps face enrollment photos and ID documents aligned on device and IMS (push + pull).
    private func reconcileRemoteChildAssets(context: ModelContext) async throws {
        let empRepo = EmployeeRepository(context: context)
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        let idDocRepo = EmployeeIdDocumentRepository(context: context)

        let syncedEmployees = try empRepo.fetchAll().filter {
            APIDecoding.normalizedServerId($0.serverId) != nil
        }
        guard !syncedEmployees.isEmpty else { return }

        async let remotePhotosTask = api.getFaceEnrollmentPhotos(includeMedia: false)
        async let remoteIdDocsTask = api.getEmployeeIdDocuments(includeMedia: false)
        let (allRemotePhotos, allRemoteIdDocs) = try await (remotePhotosTask, remoteIdDocsTask)

        var posesByServerId: [String: Set<String>] = [:]
        for dto in allRemotePhotos {
            guard let serverId = dto.employeeServerId else { continue }
            if dto.hasJpegData == true || (dto.jpegBase64?.isEmpty == false) {
                posesByServerId[serverId, default: []].insert(dto.pose)
            }
        }

        for employee in syncedEmployees where EmployeeChildSyncPreparer.hasEnrollmentPhotosOnDisk(employee) {
            guard let serverId = APIDecoding.normalizedServerId(employee.serverId) else { continue }
            _ = try photoRepo.requeueForMissingRemoteUpload(
                employeeLocalId: employee.id,
                existingRemotePosesWithJPEG: posesByServerId[serverId] ?? []
            )
            try EmployeeChildSyncPreparer.prepare(for: employee, context: context, persist: false)
        }

        var remoteIdDocMetaByServerId: [String: EmployeeIdDocumentDTO] = [:]
        for dto in allRemoteIdDocs {
            guard let serverId = dto.employeeServerId,
                  dto.hasJpegData == true || (dto.jpegBase64?.isEmpty == false) else { continue }
            remoteIdDocMetaByServerId[serverId] = dto
        }

        var pullServerIds = Set<String>()
        for employee in syncedEmployees {
            guard let serverId = APIDecoding.normalizedServerId(employee.serverId) else { continue }
            let remoteHasJPEG = remoteIdDocMetaByServerId[serverId] != nil
            if IdDocumentPhotoStore.load(employeeId: employee.id) != nil {
                _ = try idDocRepo.requeueForMissingRemoteUpload(
                    employeeLocalId: employee.id,
                    remoteHasJPEG: remoteHasJPEG
                )
                continue
            }

            guard remoteHasJPEG else { continue }
            if let localEntity = try idDocRepo.fetch(forEmployeeLocalId: employee.id),
               localEntity.syncStatus == .pending || localEntity.syncStatus == .failed {
                continue
            }
            if let remoteCaptured = remoteIdDocMetaByServerId[serverId]?.capturedAt,
               let localCaptured = employee.idDocumentCapturedAt,
               localCaptured >= remoteCaptured {
                continue
            }
            pullServerIds.insert(serverId)
        }

        if !pullServerIds.isEmpty {
            let remoteWithMedia = try await api.getEmployeeIdDocuments(includeMedia: true)
            for dto in remoteWithMedia {
                guard let serverId = dto.employeeServerId,
                      pullServerIds.contains(serverId),
                      let employee = try empRepo.fetch(serverId: serverId) else { continue }
                try idDocRepo.upsertFromRemote(dto, employeeLocalId: employee.id)
                employee.idDocumentType = IdDocumentType(rawValue: dto.idType)
                employee.idDocumentNumber = dto.idNumber ?? ""
                employee.idDocumentCapturedAt = dto.capturedAt
                try empRepo.update(employee, persist: false)
            }
            NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
        }

        try persist(context)
    }

    private func uploadPendingEmbeddings(
        context: ModelContext,
        summary: PushSyncSummary
    ) async throws -> PushSyncSummary {
        var summary = summary
        let embRepo = FaceEmbeddingRepository(context: context)
        let empRepo = EmployeeRepository(context: context)

        for employee in try empRepo.fetchAll() where EmployeeChildSyncPreparer.shouldUploadEmbeddings(for: employee) {
            try EmployeeChildSyncPreparer.prepare(for: employee, context: context, persist: false)
        }

        let pending = try embRepo.fetchPendingSync()
        guard !pending.isEmpty else { return summary }

        var ready: [FaceEmbeddingEntity] = []
        for entity in pending {
            guard entity.serverId == nil else {
                entity.syncStatus = .synced
                try embRepo.update(entity, persist: false)
                continue
            }

            if entity.employeeServerId == nil,
               let parent = try empRepo.fetch(id: entity.employeeLocalId),
               let serverId = APIDecoding.normalizedServerId(parent.serverId) {
                entity.employeeServerId = serverId
            }
            guard let parent = try empRepo.fetch(id: entity.employeeLocalId),
                  APIDecoding.normalizedServerId(parent.serverId) != nil else { continue }
            entity.employeeServerId = APIDecoding.normalizedServerId(parent.serverId)
            ready.append(entity)
        }

        try await uploadInParallel(items: ready, maxConcurrent: uploadConcurrency) { entity in
            entity.syncStatus = .syncing
            try embRepo.update(entity, persist: false)

            guard let parent = try empRepo.fetch(id: entity.employeeLocalId),
                  let serverId = APIDecoding.normalizedServerId(parent.serverId) else {
                return
            }

            let dto = FaceEmbeddingDTO(
                serverId: nil,
                localId: entity.id,
                employeeServerId: serverId,
                employeeLocalId: entity.employeeLocalId,
                pose: entity.poseRaw,
                encryptedValuesBase64: entity.encryptedValues.base64EncodedString()
            )
            do {
                let response = try await self.api.postFaceEmbedding(dto)
                entity.serverId = response.serverId
                entity.syncStatus = .synced
                try embRepo.update(entity, persist: false)
                summary.embeddingsUploaded += 1
            } catch {
                entity.syncStatus = .failed
                try? embRepo.update(entity, persist: false)
                summary.embeddingsFailed += 1
            }
        }

        try persist(context)
        return summary
    }

    private func uploadPendingEnrollmentPhotos(
        context: ModelContext,
        summary: PushSyncSummary
    ) async throws -> PushSyncSummary {
        var summary = summary
        guard shouldUploadLargeMedia() else { return summary }

        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        let empRepo = EmployeeRepository(context: context)

        for employee in try empRepo.fetchAll() where EmployeeChildSyncPreparer.shouldUploadPhotos(for: employee) {
            try EmployeeChildSyncPreparer.prepare(for: employee, context: context, persist: false)
        }

        let refreshedPending = try photoRepo.fetchPendingSync()
        guard !refreshedPending.isEmpty else { return summary }
        var ready: [FaceEnrollmentPhotoEntity] = []

        for entity in refreshedPending {
            guard entity.serverId == nil else {
                entity.syncStatus = .synced
                try photoRepo.update(entity, persist: false)
                continue
            }

            guard let parent = try empRepo.fetch(id: entity.employeeLocalId),
                  let serverId = APIDecoding.normalizedServerId(parent.serverId) else {
                continue
            }
            entity.employeeServerId = serverId

            guard EnrollmentPhotoStore.load(
                employeeId: entity.employeeLocalId,
                pose: entity.pose
            ) != nil else {
                entity.syncStatus = .failed
                try photoRepo.update(entity, persist: false)
                summary.photosSkippedNoFile += 1
                summary.lastPhotoUploadError = "Enrollment JPEG missing on device for \(entity.poseRaw)."
                continue
            }

            ready.append(entity)
        }

        try await uploadInParallel(items: ready, maxConcurrent: uploadConcurrency) { entity in
            guard let jpeg = EnrollmentPhotoStore.load(
                employeeId: entity.employeeLocalId,
                pose: entity.pose
            ) else { return }

            guard let parent = try empRepo.fetch(id: entity.employeeLocalId),
                  let serverId = APIDecoding.normalizedServerId(parent.serverId) else {
                return
            }

            entity.syncStatus = .syncing
            try photoRepo.update(entity, persist: false)

            let compressed = JPEGUploadCompressor.compressForUpload(jpeg)
            let dto = FaceEnrollmentPhotoDTO(
                serverId: nil,
                localId: entity.id,
                employeeServerId: serverId,
                employeeLocalId: entity.employeeLocalId,
                pose: entity.poseRaw,
                jpegBase64: compressed.base64EncodedString()
            )
            do {
                let response = try await self.api.postFaceEnrollmentPhoto(dto)
                entity.serverId = response.serverId
                entity.syncStatus = .synced
                try photoRepo.update(entity, persist: false)
                summary.photosUploaded += 1
            } catch {
                entity.syncStatus = .failed
                try? photoRepo.update(entity, persist: false)
                summary.photosFailed += 1
                summary.lastPhotoUploadError = error.localizedDescription
            }
        }

        try persist(context)
        return summary
    }

    private func uploadPendingIdDocuments(
        context: ModelContext,
        summary: PushSyncSummary
    ) async throws -> PushSyncSummary {
        var summary = summary
        guard shouldUploadLargeMedia() else { return summary }

        let idDocRepo = EmployeeIdDocumentRepository(context: context)
        let empRepo = EmployeeRepository(context: context)

        for employee in try empRepo.fetchAll() where EmployeeChildSyncPreparer.shouldUploadIdDocument(for: employee) {
            try EmployeeChildSyncPreparer.prepare(for: employee, context: context, persist: false)
        }

        let pending = try idDocRepo.fetchPendingSync()
        guard !pending.isEmpty else { return summary }

        try await uploadInParallel(items: pending, maxConcurrent: uploadConcurrency) { entity in
            guard let jpeg = IdDocumentPhotoStore.load(employeeId: entity.employeeLocalId) else {
                entity.syncStatus = .failed
                try? idDocRepo.update(entity, persist: false)
                summary.idDocumentsSkippedNoFile += 1
                summary.lastIdDocumentUploadError = "ID document JPEG missing on device."
                return
            }

            guard let parent = try empRepo.fetch(id: entity.employeeLocalId),
                  let serverId = APIDecoding.normalizedServerId(parent.serverId) else {
                return
            }

            entity.employeeServerId = serverId
            entity.syncStatus = .syncing
            try idDocRepo.update(entity, persist: false)

            let compressed = JPEGUploadCompressor.compressForUpload(jpeg)
            let dto = EmployeeIdDocumentDTO(
                employeeServerId: serverId,
                employeeLocalId: entity.employeeLocalId,
                idType: entity.idTypeRaw,
                idNumber: entity.idNumber.isEmpty ? nil : entity.idNumber,
                capturedAt: entity.capturedAt,
                jpegBase64: compressed.base64EncodedString()
            )
            do {
                _ = try await self.api.postEmployeeIdDocument(dto)
                entity.syncStatus = .synced
                try idDocRepo.update(entity, persist: false)
                summary.idDocumentsUploaded += 1
            } catch {
                entity.syncStatus = .failed
                try? idDocRepo.update(entity, persist: false)
                summary.idDocumentsFailed += 1
                summary.lastIdDocumentUploadError = error.localizedDescription
            }
        }

        try persist(context)
        return summary
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
                if let authoritativeTimestamp = response.timestamp {
                    record.timestamp = authoritativeTimestamp
                }
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

    /// Bidirectional job site catalog sync — runs before employee upload so assignments resolve.
    private func syncJobSites(context: ModelContext) async throws -> Int {
        for siteId in JobSiteStore.pendingDeleteIds {
            do {
                try await api.deleteJobSite(id: siteId)
                JobSiteStore.clearPendingDelete(id: siteId)
            } catch {
                // Retry on next sync if offline or server error.
            }
        }

        let remote = try await api.getJobSites()
        JobSiteStore.applyRemoteCatalog(remote)
        try remapEmployeeSiteIds(JobSiteStore.deduplicateCatalog(), context: context)

        let toPush = JobSiteStore.sitesNeedingUpload(comparedTo: remote)
        var pushed = 0
        for site in toPush {
            let dto = JobSiteDTO.fromLocal(site)
            let response = try await api.postJobSite(dto)
            if response.id != dto.id {
                JobSiteStore.remapSiteId(from: dto.id, to: response.id)
                try remapEmployeeSiteIds([dto.id: response.id], context: context)
            }
            JobSiteStore.clearPendingUpload(id: site.id)
            pushed += 1
        }

        if pushed > 0 {
            let remoteAfter = try await api.getJobSites()
            JobSiteStore.applyRemoteCatalog(remoteAfter)
        }

        try remapEmployeeSiteIds(JobSiteStore.deduplicateCatalog(), context: context)
        return pushed
    }

    private func syncDepartments() async throws {
        let remote = try await api.getDepartments()
        DepartmentStore.applyRemoteCatalog(remote)
    }

    private func remapEmployeeSiteIds(_ remap: [UUID: UUID], context: ModelContext) throws {
        guard !remap.isEmpty else { return }
        let empRepo = EmployeeRepository(context: context)
        for employee in try empRepo.fetchAll() {
            guard let assigned = employee.assignedSiteId, let canonical = remap[assigned] else { continue }
            employee.assignedSiteId = canonical
            if let site = JobSiteStore.site(id: canonical) {
                employee.assignedSiteName = site.displayTitle
                employee.assignedSiteLocation = site.locationLabel
            }
            if employee.syncStatus == .synced {
                employee.syncStatus = .pending
            }
            try empRepo.update(employee, persist: false)
        }
        try persist(context)
    }

    /// Pushes job site assignment for synced employees when local differs from IMS.
    private func pushChangedJobSiteAssignments(
        context: ModelContext,
        remoteEmployees: [EmployeeDTO]? = nil
    ) async throws {
        let empRepo = EmployeeRepository(context: context)
        let roster: [EmployeeDTO]
        if let remoteEmployees {
            roster = remoteEmployees
        } else {
            roster = try await api.getEmployees()
        }
        var remoteByServerId: [String: EmployeeDTO] = [:]
        for dto in roster {
            guard let serverId = APIDecoding.normalizedServerId(dto.serverId) else { continue }
            remoteByServerId[serverId] = dto
        }

        for employee in try empRepo.fetchAll() {
            guard employee.syncStatus == .synced,
                  let serverId = APIDecoding.normalizedServerId(employee.serverId),
                  let remote = remoteByServerId[serverId]
            else { continue }

            if employee.assignedSiteId == remote.assignedSiteId {
                let localName = employee.assignedSiteName.trimmingCharacters(in: .whitespacesAndNewlines)
                let remoteName = (remote.assignedSiteName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if localName == remoteName || (localName.isEmpty && remoteName.isEmpty) {
                    continue
                }
            }

            let dto = EmployeeDTO.fromLocalEmployee(employee, serverId: serverId)
            _ = try await api.putEmployee(dto)
            employee.updatedAt = Date()
            try empRepo.update(employee, persist: false)
        }
        try persist(context)
    }

    /// Applies IMS profile edits (name, department, job site) when the server row is newer.
    private func mergeRemoteEmployeeProfileUpdates(
        context: ModelContext,
        remoteEmployees: [EmployeeDTO]? = nil
    ) async throws -> Int {
        let empRepo = EmployeeRepository(context: context)
        let roster: [EmployeeDTO]
        if let remoteEmployees {
            roster = remoteEmployees
        } else {
            roster = try await api.getEmployees()
        }
        var merged = 0

        for dto in roster {
            guard let serverId = APIDecoding.normalizedServerId(dto.serverId),
                  let local = try empRepo.fetch(serverId: serverId),
                  local.syncStatus == .synced,
                  let remoteUpdated = dto.updatedAt,
                  remoteUpdated > local.updatedAt
            else { continue }

            JobSiteStore.applyAssignmentSnapshot(
                to: local,
                siteId: dto.assignedSiteId,
                name: dto.assignedSiteName,
                location: dto.assignedSiteLocation
            )
            local.firstName = dto.firstName
            local.lastName = dto.lastName
            local.department = dto.department
            local.position = dto.position
            local.updatedAt = remoteUpdated
            try empRepo.update(local, persist: false)
            merged += 1
        }

        if merged > 0 {
            try persist(context)
            NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
        }
        return merged
    }

    /// Pulls employees reactivated on IMS (Restore to app) that are missing on this device.
    private func importMissingRemoteEmployees(
        context: ModelContext,
        remoteEmployees: [EmployeeDTO]? = nil
    ) async throws -> Int {
        let empRepo = EmployeeRepository(context: context)
        let roster: [EmployeeDTO]
        if let remoteEmployees {
            roster = remoteEmployees
        } else {
            roster = try await api.getEmployees()
        }

        var localByServerId: [String: UUID] = [:]
        var localIds = Set<UUID>()
        for employee in try empRepo.fetchAll() {
            localIds.insert(employee.id)
            if let serverId = APIDecoding.normalizedServerId(employee.serverId) {
                localByServerId[serverId] = employee.id
            }
        }

        var importedServerIds = Set<String>()
        var imported = 0

        for dto in roster {
            guard let serverId = APIDecoding.normalizedServerId(dto.serverId) else { continue }
            if localByServerId[serverId] != nil { continue }

            if localIds.contains(dto.localId) {
                if let existing = try empRepo.fetch(id: dto.localId) {
                    try linkEmployeeToServer(
                        existing,
                        serverId: serverId,
                        context: context,
                        persist: false
                    )
                    localByServerId[serverId] = existing.id
                    importedServerIds.insert(serverId)
                }
                continue
            }

            if try empRepo.fetch(code: dto.employeeCode) != nil { continue }

            JobSiteStore.ensureFromEmployeeAssignment(
                id: dto.assignedSiteId,
                name: dto.assignedSiteName,
                location: dto.assignedSiteLocation
            )
            let employee = try empRepo.upsertFromRemote(dto)
            imported += 1
            importedServerIds.insert(serverId)
            localByServerId[serverId] = employee.id
            localIds.insert(employee.id)
        }

        guard !importedServerIds.isEmpty else { return 0 }

        let embRepo = FaceEmbeddingRepository(context: context)
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)

        for dto in try await api.getFaceEmbeddings() {
            guard let serverId = dto.employeeServerId,
                  importedServerIds.contains(serverId),
                  let localEmployeeId = localByServerId[serverId] else { continue }
            try embRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
            if let employee = try empRepo.fetch(id: localEmployeeId) {
                let entities = try embRepo.fetch(forEmployeeLocalId: localEmployeeId)
                let embeddings = entities.compactMap { try? $0.decryptedEmbedding() }
                employee.faceEmbeddings = embeddings
                employee.syncStatus = .synced
                try empRepo.update(employee, persist: false)
            }
        }

        for dto in try await api.getFaceEnrollmentPhotos(includeMedia: true) {
            guard let serverId = dto.employeeServerId,
                  importedServerIds.contains(serverId),
                  let localEmployeeId = localByServerId[serverId] else { continue }
            try photoRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
        }

        let idDocRepo = EmployeeIdDocumentRepository(context: context)
        for dto in try await api.getEmployeeIdDocuments(includeMedia: true) {
            guard let serverId = dto.employeeServerId,
                  importedServerIds.contains(serverId),
                  let localEmployeeId = localByServerId[serverId] else { continue }
            try idDocRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
            if let employee = try empRepo.fetch(id: localEmployeeId) {
                employee.idDocumentType = IdDocumentType(rawValue: dto.idType)
                employee.idDocumentNumber = dto.idNumber ?? ""
                employee.idDocumentCapturedAt = dto.capturedAt
                try empRepo.update(employee, persist: false)
            }
        }

        try persist(context)
        cachedRemoteEmployeeIndex = nil
        cachedRemoteEmployeeIndexAt = nil
        NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
        return imported
    }

    // MARK: - Restore (new device)

    /// Downloads employees + encrypted embeddings after admin authentication.
    /// App remains fully offline-capable after this completes.
    func restoreFromServer(context: ModelContext) async throws -> RestoreSummary {
        guard NetworkMonitor.shared.isConnected else { throw NetworkError.offline }

        let empRepo = EmployeeRepository(context: context)
        let embRepo = FaceEmbeddingRepository(context: context)
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        let idDocRepo = EmployeeIdDocumentRepository(context: context)

        _ = try await syncJobSites(context: context)
        try await syncDepartments()

        // INTEGRATION: GET /employees
        let remoteEmployees = try await api.getEmployees()
        var employeeCount = 0
        var localIdByServerId: [String: UUID] = [:]

        for dto in remoteEmployees {
            JobSiteStore.ensureFromEmployeeAssignment(
                id: dto.assignedSiteId,
                name: dto.assignedSiteName,
                location: dto.assignedSiteLocation
            )
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

        // INTEGRATION: GET /face-enrollment-photos (with JPEG bytes for full device restore)
        let remotePhotos = try await api.getFaceEnrollmentPhotos(includeMedia: true)
        var photoCount = 0
        var photoJPEGCount = 0
        for dto in remotePhotos {
            guard let localEmployeeId = try resolveRestoreEmployeeId(
                dtoEmployeeServerId: dto.employeeServerId,
                dtoEmployeeLocalId: dto.employeeLocalId,
                localIdByServerId: localIdByServerId,
                empRepo: empRepo
            ) else { continue }
            try photoRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
            photoCount += 1
            if let jpegBase64 = dto.jpegBase64,
               !jpegBase64.isEmpty,
               Data(base64Encoded: jpegBase64) != nil {
                photoJPEGCount += 1
            }
        }

        let remoteIdDocuments = try await api.getEmployeeIdDocuments(includeMedia: true)
        var idDocumentCount = 0
        for dto in remoteIdDocuments {
            guard let localEmployeeId = try resolveRestoreEmployeeId(
                dtoEmployeeServerId: dto.employeeServerId,
                dtoEmployeeLocalId: dto.employeeLocalId,
                localIdByServerId: localIdByServerId,
                empRepo: empRepo
            ) else { continue }
            try idDocRepo.upsertFromRemote(dto, employeeLocalId: localEmployeeId)
            idDocumentCount += 1
            if let employee = try empRepo.fetch(id: localEmployeeId) {
                employee.idDocumentType = IdDocumentType(rawValue: dto.idType)
                employee.idDocumentNumber = dto.idNumber ?? ""
                employee.idDocumentCapturedAt = dto.capturedAt
                try empRepo.update(employee, persist: false)
            }
        }

        // GET /attendance for history restore (includes punch JPEGs when include_media=1).
        let restoreStart = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let remoteAttendance = try await api.getAttendance(
            employeeServerId: nil,
            startDate: restoreStart,
            endDate: Date(),
            includeMedia: true
        )
        var attendanceCount = 0
        var punchPhotoCount = 0
        for dto in remoteAttendance {
            let already = try attExists(context: context, serverId: dto.serverId, localId: dto.localId)
            guard !already else { continue }
            guard let localEmployeeId = try resolveRestoreEmployeeId(
                dtoEmployeeServerId: dto.employeeServerId,
                dtoEmployeeLocalId: dto.employeeLocalId,
                localIdByServerId: localIdByServerId,
                empRepo: empRepo
            ) else { continue }

            let record = Attendance(
                id: dto.localId,
                serverId: dto.serverId,
                employeeId: localEmployeeId,
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
                punchPhotoCount += 1
            }
            attendanceCount += 1
        }
        try context.save()

        return RestoreSummary(
            employees: employeeCount,
            embeddings: embeddingCount,
            enrollmentPhotos: photoCount,
            enrollmentPhotosWithJPEG: photoJPEGCount,
            attendance: attendanceCount,
            punchPhotos: punchPhotoCount
        )
    }

    private func resolveRestoreEmployeeId(
        dtoEmployeeServerId: String?,
        dtoEmployeeLocalId: UUID,
        localIdByServerId: [String: UUID],
        empRepo: EmployeeRepository
    ) throws -> UUID? {
        if let serverId = dtoEmployeeServerId, let mapped = localIdByServerId[serverId] {
            return mapped
        }
        if let existing = try empRepo.fetch(id: dtoEmployeeLocalId) {
            return existing.id
        }
        if let serverId = dtoEmployeeServerId, let existing = try empRepo.fetch(serverId: serverId) {
            return existing.id
        }
        return nil
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
        let enrollmentPhotosWithJPEG: Int
        let attendance: Int
        let punchPhotos: Int

        var successMessage: String {
            var parts = [
                "\(employees) employees",
                "\(embeddings) face templates",
                "\(enrollmentPhotosWithJPEG) enrollment photos",
                "\(attendance) attendance records"
            ]
            if punchPhotos > 0 {
                parts.append("\(punchPhotos) punch photos")
            }
            return "Restored " + parts.joined(separator: ", ") + "."
        }
    }
}
