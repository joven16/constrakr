//
//  EmployeeService.swift
//  ConsTrakr
//
//  CHANGE: Duplicate prevention for employee code, full name, and face embeddings
//  before saving a new registration.
//

import Foundation
import SwiftData

@MainActor
final class EmployeeService {
    private let repository: EmployeeRepository
    private let embeddingRepository: FaceEmbeddingRepository
    private let matchingService = FaceMatchingService()
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        self.repository = EmployeeRepository(context: context)
        self.embeddingRepository = FaceEmbeddingRepository(context: context)
    }

    func allEmployees(search: String = "") throws -> [Employee] {
        try repository.fetchAll(search: search)
    }

    func employee(id: UUID) throws -> Employee? {
        try repository.fetch(id: id)
    }

    func register(
        employeeCode: String,
        firstName: String,
        lastName: String,
        department: String,
        embeddings: [FaceEmbedding],
        faceDepthSignature: FaceDepthSignature? = nil,
        enrollmentPhotos: [FacePose: Data] = [:]
    ) throws -> Employee {
        let code = employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dept = department.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !code.isEmpty else { throw ServiceError.invalidInput("Employee code is required.") }
        guard !first.isEmpty else { throw ServiceError.invalidInput("First name is required.") }
        guard !last.isEmpty else { throw ServiceError.invalidInput("Last name is required.") }
        guard !embeddings.isEmpty else { throw ServiceError.invalidInput("Face enrollment is required.") }

        // Duplicate: Employee ID / code
        if try repository.fetch(code: code) != nil {
            throw ServiceError.duplicateCode
        }

        // Duplicate: full name
        if try repository.fetchByFullName(firstName: first, lastName: last) != nil {
            throw ServiceError.duplicateName
        }

        // Duplicate: face already registered (compare against every enrolled embedding)
        if let match = try matchingEnrolledFace(probes: embeddings) {
            throw ServiceError.duplicateFace(name: match.employeeName, code: match.employeeCode)
        }

        let employee = Employee(
            employeeCode: code,
            firstName: first,
            lastName: last,
            department: dept.isEmpty ? "General" : dept,
            faceEmbeddings: embeddings,
            faceDepthSignature: faceDepthSignature,
            syncStatus: .pending
        )
        try repository.save(employee)

        var entities: [FaceEmbeddingEntity] = []
        for embedding in embeddings {
            let ciphertext = try EmbeddingCrypto.encryptValues(embedding.values)
            let entity = FaceEmbeddingEntity(
                employeeLocalId: employee.id,
                employeeServerId: nil,
                pose: embedding.pose,
                encryptedValues: ciphertext,
                syncStatus: .pending
            )
            entities.append(entity)
        }
        try embeddingRepository.saveAll(entities)

        var photoEntities: [FaceEnrollmentPhotoEntity] = []
        for pose in enrollmentPhotos.keys {
            photoEntities.append(
                FaceEnrollmentPhotoEntity(
                    employeeLocalId: employee.id,
                    employeeServerId: nil,
                    pose: pose,
                    syncStatus: .pending
                )
            )
        }
        if !photoEntities.isEmpty {
            let photoRepository = FaceEnrollmentPhotoRepository(context: context)
            try photoRepository.saveAll(photoEntities)
        }
        try EnrollmentPhotoStore.saveAll(employeeId: employee.id, photos: enrollmentPhotos)

        return employee
    }

    /// Returns a match when the probe face already belongs to an enrolled employee.
    func matchingEnrolledFace(probes: [FaceEmbedding]) throws -> FaceMatchResult? {
        let existing = try repository.fetchAll().filter { employee in
            employee.isEnrolled
                && employee.faceEmbeddings.contains { $0.values.count == FaceEmbedding.expectedDimension }
        }
        return matchingService.findDuplicateFace(probes: probes, against: existing)
    }

    func delete(_ employee: Employee) throws {
        EnrollmentPhotoStore.delete(employeeId: employee.id)
        try embeddingRepository.delete(forEmployeeLocalId: employee.id)
        let photoRepository = FaceEnrollmentPhotoRepository(context: context)
        try photoRepository.delete(forEmployeeLocalId: employee.id)
        try repository.delete(employee)
    }

    func updateProfile(
        employee: Employee,
        employeeCode: String,
        firstName: String,
        lastName: String,
        department: String
    ) throws {
        let code = employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dept = department.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !code.isEmpty else { throw ServiceError.invalidInput("Employee code is required.") }
        guard !first.isEmpty else { throw ServiceError.invalidInput("First name is required.") }
        guard !last.isEmpty else { throw ServiceError.invalidInput("Last name is required.") }

        if let other = try repository.fetch(code: code), other.id != employee.id {
            throw ServiceError.duplicateCode
        }
        if let other = try repository.fetchByFullName(firstName: first, lastName: last),
           other.id != employee.id {
            throw ServiceError.duplicateName
        }

        employee.employeeCode = code
        employee.firstName = first
        employee.lastName = last
        employee.department = dept.isEmpty ? "General" : dept
        employee.updatedAt = Date()
        employee.syncStatus = .pending
        try repository.update(employee)
        NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
    }

    func count() throws -> Int {
        try repository.count()
    }

    enum ServiceError: LocalizedError {
        case invalidInput(String)
        case duplicateCode
        case duplicateName
        case duplicateFace(name: String, code: String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let message): return message
            case .duplicateCode: return "An employee with this ID already exists."
            case .duplicateName: return "An employee with this name already exists."
            case .duplicateFace(let name, let code):
                return "This face already belongs to \(name) (\(code))."
            }
        }
    }
}
