//
//  APIEndpoints.swift
//  ConsTrakr
//
//  CHANGE: Placeholder REST surface aligned to offline-first sync + restore.
//  INTEGRATION: Point base URL at your real HTTPS backend when ready.
//

import Foundation

enum APIEndpoint {
    // Employees
    case getEmployees
    case postEmployee
    // Face embeddings (encrypted payloads only)
    case getFaceEmbeddings
    case postFaceEmbedding
    // Enrollment face JPEGs (one row per pose)
    case getFaceEnrollmentPhotos
    case postFaceEnrollmentPhoto
    // Attendance
    case getAttendance
    case postAttendance
    // Auth / health (restore gate)
    case adminLogin
    case healthCheck

    var path: String {
        switch self {
        case .getEmployees, .postEmployee:
            return "/employees"
        case .getFaceEmbeddings, .postFaceEmbedding:
            return "/face-embeddings"
        case .getFaceEnrollmentPhotos, .postFaceEnrollmentPhoto:
            return "/face-enrollment-photos"
        case .getAttendance, .postAttendance:
            return "/attendance"
        case .adminLogin:
            return "/auth/admin/login"
        case .healthCheck:
            return "/health"
        }
    }

    var method: String {
        switch self {
        case .postEmployee, .postFaceEmbedding, .postFaceEnrollmentPhoto, .postAttendance, .adminLogin:
            return "POST"
        case .getEmployees, .getFaceEmbeddings, .getFaceEnrollmentPhotos, .getAttendance, .healthCheck:
            return "GET"
        }
    }
}

// MARK: - DTOs (local id vs server id kept explicit)

struct EmployeeDTO: Codable, Identifiable {
    /// Backend employee id when known; for POST responses.
    let serverId: String?
    /// Client local UUID — backend should store for idempotent upserts.
    let localId: UUID
    let employeeCode: String
    let firstName: String
    let lastName: String
    let department: String
    /// AES-GCM encrypted TrueDepth signature (empty when device has no TrueDepth).
    let encryptedDepthSignatureBase64: String?

    var id: UUID { localId }

    init(
        serverId: String?,
        localId: UUID,
        employeeCode: String,
        firstName: String,
        lastName: String,
        department: String,
        encryptedDepthSignatureBase64: String? = nil
    ) {
        self.serverId = serverId
        self.localId = localId
        self.employeeCode = employeeCode
        self.firstName = firstName
        self.lastName = lastName
        self.department = department
        self.encryptedDepthSignatureBase64 = encryptedDepthSignatureBase64
    }
}

struct EmployeeUpsertResponse: Codable {
    let serverId: String
    let localId: UUID
}

struct FaceEmbeddingDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let pose: String
    /// Base64 of AES-GCM ciphertext — never plaintext floats over the wire.
    let encryptedValuesBase64: String
}

struct FaceEmbeddingUpsertResponse: Codable {
    let serverId: String
    let localId: UUID
}

struct FaceEnrollmentPhotoDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let pose: String
    /// JPEG bytes, base64 — enrollment face crop for web dashboard display.
    let jpegBase64: String
}

struct FaceEnrollmentPhotoUpsertResponse: Codable {
    let serverId: String
    let localId: UUID
}

struct AttendanceDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let checkType: String
    let timestamp: Date
    let confidenceScore: Double
    let notes: String?
    /// Optional punch-time face crop (JPEG, base64).
    let punchPhotoBase64: String?

    init(
        serverId: String?,
        localId: UUID,
        employeeServerId: String?,
        employeeLocalId: UUID,
        checkType: String,
        timestamp: Date,
        confidenceScore: Double,
        notes: String?,
        punchPhotoBase64: String? = nil
    ) {
        self.serverId = serverId
        self.localId = localId
        self.employeeServerId = employeeServerId
        self.employeeLocalId = employeeLocalId
        self.checkType = checkType
        self.timestamp = timestamp
        self.confidenceScore = confidenceScore
        self.notes = notes
        self.punchPhotoBase64 = punchPhotoBase64
    }
}

struct AttendanceUpsertResponse: Codable {
    let serverId: String
    let localId: UUID
}

struct AdminLoginRequest: Codable {
    let username: String
    let password: String
}

struct AdminLoginResponse: Codable {
    let accessToken: String
    let expiresIn: Int?
}

/// Legacy batch response shape kept for compatibility with older SyncQueue call sites.
struct AttendanceSyncResponse: Codable {
    let syncedIds: [UUID]
    let failedIds: [UUID]
}
