//
//  EmployeeRepository.swift
//  ConsTrakr
//
//  CHANGE: Pending sync fetch + upsert-by-serverId/code for restore (duplicate-safe).
//

import Foundation
import SwiftData

@MainActor
final class EmployeeRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll(search: String = "") throws -> [Employee] {
        var descriptor = FetchDescriptor<Employee>(
            sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
        )
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            descriptor.predicate = #Predicate { employee in
                employee.firstName.localizedStandardContains(query)
                    || employee.lastName.localizedStandardContains(query)
                    || employee.employeeCode.localizedStandardContains(query)
                    || employee.department.localizedStandardContains(query)
            }
        }
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) throws -> Employee? {
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetch(code: String) throws -> Employee? {
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.employeeCode == code }
        )
        return try context.fetch(descriptor).first
    }

    func fetchByFullName(firstName: String, lastName: String) throws -> Employee? {
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { employee in
                employee.firstName == firstName && employee.lastName == lastName
            }
        )
        return try context.fetch(descriptor).first
    }

    func fetch(serverId: String) throws -> Employee? {
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try context.fetch(descriptor).first
    }

    /// New employees awaiting first upload (any row without a backend id).
    func fetchPendingSync() throws -> [Employee] {
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { employee in
                employee.serverId == nil
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    /// Fixes rows marked synced locally but never received a server id (legacy mock seed).
    func repairStaleSyncState() throws -> Int {
        let synced = SyncStatus.synced.rawValue
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { employee in
                employee.serverId == nil && employee.syncStatusRaw == synced
            }
        )
        let stale = try context.fetch(descriptor)
        for employee in stale {
            employee.syncStatus = .pending
            employee.updatedAt = Date()
        }
        if !stale.isEmpty {
            try context.save()
        }
        return stale.count
    }

    /// Profile edits on employees already synced to the backend.
    func fetchPendingUpdates() throws -> [Employee] {
        let pending = SyncStatus.pending.rawValue
        let failed = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate { employee in
                (employee.syncStatusRaw == pending || employee.syncStatusRaw == failed)
                    && employee.serverId != nil
            },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        return try context.fetch(descriptor)
    }

    func pendingCount() throws -> Int {
        try fetchPendingSync().count + fetchPendingUpdates().count
    }

    func save(_ employee: Employee) throws {
        context.insert(employee)
        try context.save()
    }

    func update(_ employee: Employee, persist: Bool = true) throws {
        employee.updatedAt = Date()
        if persist {
            try context.save()
        }
    }

    func delete(_ employee: Employee) throws {
        context.delete(employee)
        try context.save()
    }

    func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<Employee>())
    }

    /// Restore helper: merge remote employee without duplicating by serverId or employeeCode.
    @discardableResult
    func upsertFromRemote(_ dto: EmployeeDTO) throws -> Employee {
        if let serverId = dto.serverId, let existing = try fetch(serverId: serverId) {
            existing.firstName = dto.firstName
            existing.lastName = dto.lastName
            existing.department = dto.department
            existing.employeeCode = dto.employeeCode
            JobSiteStore.applyAssignmentSnapshot(
                to: existing,
                siteId: dto.assignedSiteId,
                name: dto.assignedSiteName,
                location: dto.assignedSiteLocation
            )
            existing.syncStatus = .synced
            existing.updatedAt = dto.updatedAt ?? Date()
            applyRemoteDepthSignature(dto, to: existing)
            try context.save()
            return existing
        }
        if let existing = try fetch(code: dto.employeeCode) {
            existing.serverId = dto.serverId ?? existing.serverId
            existing.firstName = dto.firstName
            existing.lastName = dto.lastName
            existing.department = dto.department
            JobSiteStore.applyAssignmentSnapshot(
                to: existing,
                siteId: dto.assignedSiteId,
                name: dto.assignedSiteName,
                location: dto.assignedSiteLocation
            )
            existing.syncStatus = .synced
            existing.updatedAt = dto.updatedAt ?? Date()
            applyRemoteDepthSignature(dto, to: existing)
            try context.save()
            return existing
        }

        let employee = Employee(
            id: dto.localId,
            serverId: dto.serverId,
            employeeCode: dto.employeeCode,
            firstName: dto.firstName,
            lastName: dto.lastName,
            department: dto.department,
            assignedSiteId: dto.assignedSiteId,
            assignedSiteName: dto.assignedSiteName ?? "",
            assignedSiteLocation: dto.assignedSiteLocation ?? "",
            faceEmbeddings: [],
            syncStatus: .synced
        )
        JobSiteStore.ensureFromEmployeeAssignment(
            id: dto.assignedSiteId,
            name: dto.assignedSiteName,
            location: dto.assignedSiteLocation
        )
        applyRemoteDepthSignature(dto, to: employee)
        try save(employee)
        return employee
    }

    private func applyRemoteDepthSignature(_ dto: EmployeeDTO, to employee: Employee) {
        guard let base64 = dto.encryptedDepthSignatureBase64,
              let data = Data(base64Encoded: base64),
              !data.isEmpty else { return }
        employee.faceDepthSignatureData = data
    }
}
