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
}

struct EmployeeSyncStatusItem: Identifiable {
    let id: UUID
    let employeeCode: String
    let name: String
    let localServerId: String?
    let status: EmployeeCloudStatus
}

struct EmployeeSyncReport {
    let localTotal: Int
    let confirmedOnIMS: Int
    let needsUpload: Int
    let remoteTotal: Int
    let linkedFromServer: Int
    let resetPhantomIds: Int
    let items: [EmployeeSyncStatusItem]

    var summaryLine: String {
        "\(confirmedOnIMS)/\(localTotal) employees on IMS (\(remoteTotal) on server)"
    }

    func status(for employeeId: UUID) -> EmployeeCloudStatus {
        items.first(where: { $0.id == employeeId })?.status ?? .notChecked
    }
}

@MainActor
enum EmployeeSyncChecker {
    /// Pulls IMS roster and marks each local employee as on IMS or needs upload.
    /// When `repair` is true, links missing server ids and clears phantom local ids.
    static func check(context: ModelContext, repair: Bool = false) async throws -> EmployeeSyncReport {
        let repo = EmployeeRepository(context: context)
        let local = try repo.fetchAll()
        _ = try repo.repairStaleSyncState()

        guard AdminSession.shared.isAuthenticated,
              await APIService.shared.hasAuthToken(),
              NetworkMonitor.shared.isConnected else {
            let items = local.map { employee in
                EmployeeSyncStatusItem(
                    id: employee.id,
                    employeeCode: employee.employeeCode,
                    name: employee.fullName,
                    localServerId: employee.serverId,
                    status: employee.serverId == nil ? .needsUpload : .notChecked
                )
            }
            let needs = items.filter { $0.status == .needsUpload }.count
            return EmployeeSyncReport(
                localTotal: local.count,
                confirmedOnIMS: items.filter { $0.status == .onIMS }.count,
                needsUpload: needs,
                remoteTotal: 0,
                linkedFromServer: 0,
                resetPhantomIds: 0,
                items: items
            )
        }

        await APIService.shared.warmConnection()
        let remote = try await APIService.shared.getEmployees()
        let index = RemoteEmployeeIndex(remote: remote)

        var confirmed = 0
        var needsUpload = 0
        var linked = 0
        var reset = 0
        var items: [EmployeeSyncStatusItem] = []

        for employee in local {
            var status: EmployeeCloudStatus = .needsUpload

            if let remoteDTO = index.match(for: employee),
               let serverId = APIDecoding.normalizedServerId(remoteDTO.serverId) {
                status = .onIMS
                confirmed += 1

                if repair, employee.serverId != serverId {
                    employee.serverId = serverId
                    employee.syncStatus = .synced
                    linked += 1
                }
            } else if repair,
                      APIDecoding.normalizedServerId(employee.serverId) != nil {
                employee.serverId = nil
                employee.syncStatus = .pending
                reset += 1
                needsUpload += 1
            } else {
                needsUpload += 1
            }

            items.append(
                EmployeeSyncStatusItem(
                    id: employee.id,
                    employeeCode: employee.employeeCode,
                    name: employee.fullName,
                    localServerId: employee.serverId,
                    status: status
                )
            )
        }

        if repair && (linked > 0 || reset > 0) {
            try context.save()
        }

        return EmployeeSyncReport(
            localTotal: local.count,
            confirmedOnIMS: confirmed,
            needsUpload: needsUpload,
            remoteTotal: remote.count,
            linkedFromServer: linked,
            resetPhantomIds: reset,
            items: items
        )
    }
}

// Shared with SyncService — same matching rules as upload dedup.
struct RemoteEmployeeIndex {
    private let byLocalId: [UUID: EmployeeDTO]
    private let byEmployeeCode: [String: EmployeeDTO]

    init(remote: [EmployeeDTO]) {
        var byLocalId: [UUID: EmployeeDTO] = [:]
        var byEmployeeCode: [String: EmployeeDTO] = [:]
        for dto in remote {
            byLocalId[dto.localId] = dto
            byEmployeeCode[dto.employeeCode.uppercased()] = dto
        }
        self.byLocalId = byLocalId
        self.byEmployeeCode = byEmployeeCode
    }

    func match(for employee: Employee) -> EmployeeDTO? {
        if let dto = byLocalId[employee.id] { return dto }
        return byEmployeeCode[employee.employeeCode.uppercased()]
    }
}
