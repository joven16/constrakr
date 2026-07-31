//
//  APIEndpoints.swift
//  ConsTrac
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
        case .postEmployee, .postFaceEmbedding, .postAttendance, .adminLogin:
            return "POST"
        case .getEmployees, .getFaceEmbeddings, .getAttendance, .healthCheck:
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

    var id: UUID { localId }
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

struct AttendanceDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let checkType: String
    let timestamp: Date
    let confidenceScore: Double
    let notes: String?
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
