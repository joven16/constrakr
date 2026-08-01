//
//  Employee.swift
//  ConsTrakr
//
//  CHANGE: Added `serverId` + `syncStatus` for offline-first sync.
//  CHANGE: `faceEmbeddingsData` is now AES-GCM encrypted (with plaintext JSON fallback for migration).
//

import Foundation
import SwiftData

@Model
final class Employee {
    /// Local-only primary key. Never treat this as the backend id.
    @Attribute(.unique) var id: UUID
    /// Backend id from POST/GET /employees — nil until synced or restored.
    var serverId: String?
    @Attribute(.unique) var employeeCode: String
    var firstName: String
    var lastName: String
    var department: String
    /// Encrypted JSON blob of `[FaceEmbedding]` for fast local matching after decrypt.
    var faceEmbeddingsData: Data
    var syncStatusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        employeeCode: String,
        firstName: String,
        lastName: String,
        department: String,
        faceEmbeddings: [FaceEmbedding] = [],
        syncStatus: SyncStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverId = serverId
        self.employeeCode = employeeCode
        self.firstName = firstName
        self.lastName = lastName
        self.department = department
        // CHANGE: encrypt before persisting (offline-first security requirement).
        self.faceEmbeddingsData = (try? EmbeddingCrypto.encryptEmbeddings(faceEmbeddings)) ?? Data()
        self.syncStatusRaw = syncStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var faceEmbeddings: [FaceEmbedding] {
        get {
            guard !faceEmbeddingsData.isEmpty else { return [] }
            // Preferred path: decrypt AES-GCM payload.
            if let decrypted = try? EmbeddingCrypto.decryptEmbeddings(faceEmbeddingsData) {
                return decrypted
            }
            // Migration fallback: legacy unencrypted JSON from earlier builds.
            return (try? JSONDecoder().decode([FaceEmbedding].self, from: faceEmbeddingsData)) ?? []
        }
        set {
            faceEmbeddingsData = (try? EmbeddingCrypto.encryptEmbeddings(newValue)) ?? Data()
            updatedAt = Date()
            // New/changed embeddings must be re-uploaded.
            if syncStatus == .synced {
                syncStatus = .pending
            }
        }
    }

    var isEnrolled: Bool {
        !faceEmbeddings.isEmpty
    }
}
