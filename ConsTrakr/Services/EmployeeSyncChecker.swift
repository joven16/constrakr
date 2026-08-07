//
//  EmployeeSyncChecker.swift
//  ConsTrakr
//
//  Compares local employees against GET /constrakr-api/employees on IMS.
//

import Foundation
import SwiftData

enum EmployeeCloudStatus: String {
    case onIMS = "On IMS"
    case needsUpload = "Not on IMS"
    case notChecked = "Not checked"

    var colorName: String {
        switch self {
        case .onIMS: return "green"
        case .needsUpload: return "orange"
        case .notChecked: return "secondary"
        }
    }

    var displayName: String {
        switch self {
        case .onIMS: return "On IMS"
        case .needsUpload: return "Not on IMS"
        case .notChecked: return "Not checked"
        }
    }
}

struct EmployeeSyncStatusItem: Identifiable {
    let id: UUID
    let employeeCode: String
    let name: String
    let localServerId: String?
    let status: EmployeeCloudStatus
    let localSyncStatus: SyncStatus
    let localUpdatedAt: Date
    let imsUpdatedAt: Date?
    let checkedAt: Date

    var imsDateLine: String {
        switch status {
        case .onIMS:
            return imsUpdatedAt.map { "IMS \($0.attendanceDisplay)" } ?? "On IMS"
        case .needsUpload:
            return "Local \(localUpdatedAt.attendanceDisplay)"
        case .notChecked:
            return "Tap Sync or Check IMS"
        }
    }
}

struct EmployeeSyncReport {
    let localTotal: Int
    let confirmedOnIMS: Int
    let needsUpload: Int
    let remoteTotal: Int
    let remoteRawCount: Int
    let remoteSkippedDecode: Int
    let linkedFromServer: Int
    let resetPhantomIds: Int
    let items: [EmployeeSyncStatusItem]
    let checkedAt: Date
    let remoteEmployeeCodes: [String]
    /// Set when IMS could not be queried (offline, not signed in, etc.).
    let statusNote: String?

    var summaryLine: String {
        if let statusNote {
            return statusNote
        }
        if remoteSkippedDecode > 0 {
            return "\(confirmedOnIMS)/\(localTotal) on IMS · \(remoteSkippedDecode) IMS row(s) unreadable"
        }
        return "\(confirmedOnIMS)/\(localTotal) on IMS · \(remoteTotal) on server · checked \(checkedAt.attendanceDisplay)"
    }

    func status(for employeeId: UUID) -> EmployeeCloudStatus {
        items.first(where: { $0.id == employeeId })?.status ?? .notChecked
    }

    func item(for employeeId: UUID) -> EmployeeSyncStatusItem? {
        items.first(where: { $0.id == employeeId })
    }
}

@MainActor
enum EmployeeSyncChecker {
    /// Pulls IMS roster and marks each local employee as on IMS or needs upload.
    /// When `repair` is true, links missing server ids and clears phantom local ids.
    /// Pass `preloadedParsed` to reuse a roster already fetched during sync (avoids duplicate GET).
    static func check(
        context: ModelContext,
        repair: Bool = false,
        preloadedParsed: APIDecoding.EmployeeListDecodeResult? = nil
    ) async throws -> EmployeeSyncReport {
        let checkedAt = Date()
        let repo = EmployeeRepository(context: context)
        let local = try repo.fetchAll()
        _ = try repo.repairStaleSyncState()

        let isOnline = NetworkMonitor.shared.isConnected
        let hasToken = await APIService.shared.hasAuthToken()
        let isSignedIn = AdminSession.shared.isAuthenticated && hasToken

        guard isSignedIn, isOnline else {
            let statusNote: String?
            if !isOnline {
                statusNote = "No internet connection. Connect to check IMS."
            } else if !AdminSession.shared.isAuthenticated || !hasToken {
                statusNote = "Sign in under Settings → IMS Sync & Restore before checking IMS."
            } else {
                statusNote = "Could not reach IMS."
            }

            let items = local.map { employee in
                EmployeeSyncStatusItem(
                    id: employee.id,
                    employeeCode: employee.employeeCode,
                    name: employee.fullName,
                    localServerId: employee.serverId,
                    status: employee.serverId == nil ? .needsUpload : .notChecked,
                    localSyncStatus: employee.syncStatus,
                    localUpdatedAt: employee.updatedAt,
                    imsUpdatedAt: nil,
                    checkedAt: checkedAt
                )
            }
            let needs = items.filter { $0.status == .needsUpload }.count
            return EmployeeSyncReport(
                localTotal: local.count,
                confirmedOnIMS: items.filter { $0.status == .onIMS }.count,
                needsUpload: needs,
                remoteTotal: 0,
                remoteRawCount: 0,
                remoteSkippedDecode: 0,
                linkedFromServer: 0,
                resetPhantomIds: 0,
                items: items,
                checkedAt: checkedAt,
                remoteEmployeeCodes: [],
                statusNote: statusNote
            )
        }

        let parsed: APIDecoding.EmployeeListDecodeResult
        if let preloadedParsed {
            parsed = preloadedParsed
        } else {
            await APIService.shared.warmConnection()
            let listData = try await APIService.shared.fetchEmployeesData()
            parsed = APIDecoding.decodeEmployees(from: listData)
        }
        var index = RemoteEmployeeIndex(remote: parsed.employees)

        var confirmed = 0
        var needsUpload = 0
        var linked = 0
        var reset = 0
        var items: [EmployeeSyncStatusItem] = []
        var needsSave = false

        for employee in local {
            var status: EmployeeCloudStatus = .needsUpload
            var imsUpdatedAt: Date?
            var remoteDTO = index.match(for: employee)

            if remoteDTO == nil {
                remoteDTO = await lookupRemoteEmployee(for: employee)
                if let remoteDTO {
                    index.insert(remoteDTO)
                }
            }

            if let remoteDTO {
                status = .onIMS
                imsUpdatedAt = remoteDTO.updatedAt
                confirmed += 1

                if repair, let serverId = index.resolvedServerId(for: employee) {
                    if employee.serverId != serverId {
                        employee.serverId = serverId
                        employee.syncStatus = .synced
                        linked += 1
                        needsSave = true
                    } else if employee.syncStatus != .synced {
                        employee.syncStatus = .synced
                        needsSave = true
                    }
                    try EmployeeChildSyncPreparer.prepare(for: employee, context: context, persist: false)
                }
            } else if repair,
                      APIDecoding.normalizedServerId(employee.serverId) != nil {
                employee.serverId = nil
                employee.syncStatus = .pending
                reset += 1
                needsUpload += 1
                needsSave = true
            } else {
                needsUpload += 1
                if repair, employee.serverId == nil, employee.syncStatus == .synced {
                    employee.syncStatus = .pending
                    needsSave = true
                }
            }

            items.append(
                EmployeeSyncStatusItem(
                    id: employee.id,
                    employeeCode: employee.employeeCode,
                    name: employee.fullName,
                    localServerId: employee.serverId,
                    status: status,
                    localSyncStatus: employee.syncStatus,
                    localUpdatedAt: employee.updatedAt,
                    imsUpdatedAt: imsUpdatedAt,
                    checkedAt: checkedAt
                )
            )
        }

        if repair && needsSave {
            try context.save()
        }

        return EmployeeSyncReport(
            localTotal: local.count,
            confirmedOnIMS: confirmed,
            needsUpload: needsUpload,
            remoteTotal: index.allEmployees.count,
            remoteRawCount: parsed.rawCount,
            remoteSkippedDecode: parsed.skippedCount,
            linkedFromServer: linked,
            resetPhantomIds: reset,
            items: items,
            checkedAt: checkedAt,
            remoteEmployeeCodes: index.allEmployeeCodes,
            statusNote: statusNote(
                local: local,
                remoteCodes: index.allEmployeeCodes,
                remoteTotal: index.allEmployees.count,
                remoteRawCount: parsed.rawCount,
                remoteSkippedDecode: parsed.skippedCount,
                needsUpload: needsUpload
            )
        )
    }

    private static func lookupRemoteEmployee(for employee: Employee) async -> EmployeeDTO? {
        if let serverId = APIDecoding.normalizedServerId(employee.serverId),
           let matches = try? await APIService.shared.getEmployees(serverId: serverId),
           let dto = matches.first {
            return dto
        }
        if let matches = try? await APIService.shared.getEmployees(localId: employee.id),
           let dto = matches.first {
            return dto
        }
        if let matches = try? await APIService.shared.getEmployees(employeeCode: employee.employeeCode),
           let dto = matches.first {
            return dto
        }
        let normalized = APIDecoding.normalizeEmployeeCode(employee.employeeCode)
        if normalized != employee.employeeCode.uppercased(),
           let matches = try? await APIService.shared.getEmployees(employeeCode: normalized),
           let dto = matches.first {
            return dto
        }
        return nil
    }

    private static func statusNote(
        local: [Employee],
        remoteCodes: [String],
        remoteTotal: Int,
        remoteRawCount: Int,
        remoteSkippedDecode: Int,
        needsUpload: Int
    ) -> String? {
        if remoteRawCount > 0, remoteSkippedDecode > 0 {
            return "IMS sent \(remoteRawCount) employee(s) but \(remoteSkippedDecode) could not be read. Tap Sync Now."
        }
        guard !local.isEmpty, needsUpload > 0 else { return nil }

        let localCodes = local.map(\.employeeCode).sorted()
        if remoteTotal == 0 {
            return "IMS returned 0 employees to the phone. Sign in, tap Sync Now, or confirm codes match IMS web (\(localCodes.joined(separator: ", ")))."
        }

        let remoteNormalized = Set(remoteCodes.map { APIDecoding.normalizeEmployeeCode($0) })
        let unmatched = local.filter {
            !remoteNormalized.contains(APIDecoding.normalizeEmployeeCode($0.employeeCode))
        }
        guard !unmatched.isEmpty else { return nil }

        let imsList = remoteCodes.sorted().joined(separator: ", ")
        let phoneList = unmatched.map(\.employeeCode).sorted().joined(separator: ", ")
        return "IMS has: \(imsList). Phone not matched: \(phoneList). Codes must match for backup."
    }
}

// Shared with SyncService — same matching rules as upload dedup.
struct RemoteEmployeeIndex {
    private var byLocalId: [UUID: EmployeeDTO]
    private var byEmployeeCode: [String: EmployeeDTO]
    private var byServerId: [String: EmployeeDTO]

    init(remote: [EmployeeDTO]) {
        self.byLocalId = [:]
        self.byEmployeeCode = [:]
        self.byServerId = [:]
        for dto in remote {
            insert(dto)
        }
    }

    var allEmployees: [EmployeeDTO] {
        Array(byLocalId.values)
    }

    var allEmployeeCodes: [String] {
        allEmployees.map(\.employeeCode)
    }

    mutating func insert(_ dto: EmployeeDTO) {
        byLocalId[dto.localId] = dto
        byEmployeeCode[Self.normalize(dto.employeeCode)] = dto
        if let serverId = APIDecoding.normalizedServerId(dto.serverId) {
            byServerId[serverId] = dto
        }
    }

    func match(for employee: Employee) -> EmployeeDTO? {
        if let dto = byLocalId[employee.id] { return dto }
        if let serverId = APIDecoding.normalizedServerId(employee.serverId),
           let dto = byServerId[serverId] {
            return dto
        }
        if let dto = byEmployeeCode[Self.normalize(employee.employeeCode)] {
            return dto
        }
        return nil
    }

    func resolvedServerId(for employee: Employee) -> String? {
        guard let dto = match(for: employee) else { return nil }
        return APIDecoding.normalizedServerId(dto.serverId)
            ?? APIDecoding.normalizedServerId(employee.serverId)
    }

    private static func normalize(_ code: String) -> String {
        APIDecoding.normalizeEmployeeCode(code)
    }
}
