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
    var position: String
    /// Job site this employee must be at for Time In / Time Out.
    var assignedSiteId: UUID?
    /// Denormalized from IMS sync — used when the local site catalog is stale.
    var assignedSiteName: String = ""
    var assignedSiteLocation: String = ""
    /// Encrypted JSON blob of `[FaceEmbedding]` for fast local matching after decrypt.
    var faceEmbeddingsData: Data
    /// Encrypted TrueDepth face geometry from enrollment (empty if not scanned / no TrueDepth).
    var faceDepthSignatureData: Data = Data()
    var syncStatusRaw: String
    /// Primary government ID type captured during registration (empty if skipped).
    var idDocumentTypeRaw: String = ""
    /// Optional ID number entered or typed during registration.
    var idDocumentNumber: String = ""
    /// When the ID photo was captured on this device.
    var idDocumentCapturedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        employeeCode: String,
        firstName: String,
        lastName: String,
        department: String,
        position: String = "",
        assignedSiteId: UUID? = nil,
        assignedSiteName: String = "",
        assignedSiteLocation: String = "",
        faceEmbeddings: [FaceEmbedding] = [],
        faceDepthSignature: FaceDepthSignature? = nil,
        idDocumentType: IdDocumentType? = nil,
        idDocumentNumber: String = "",
        idDocumentCapturedAt: Date? = nil,
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
        self.position = position
        self.assignedSiteId = assignedSiteId
        self.assignedSiteName = assignedSiteName
        self.assignedSiteLocation = assignedSiteLocation
        // CHANGE: encrypt before persisting (offline-first security requirement).
        self.faceEmbeddingsData = (try? EmbeddingCrypto.encryptEmbeddings(faceEmbeddings)) ?? Data()
        if let faceDepthSignature {
            self.faceDepthSignatureData =
                (try? EmbeddingCrypto.encryptDepthSignature(faceDepthSignature)) ?? Data()
        } else {
            self.faceDepthSignatureData = Data()
        }
        self.syncStatusRaw = syncStatus.rawValue
        self.idDocumentTypeRaw = idDocumentType?.rawValue ?? ""
        self.idDocumentNumber = idDocumentNumber
        self.idDocumentCapturedAt = idDocumentCapturedAt
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

    var idDocumentType: IdDocumentType? {
        get {
            guard !idDocumentTypeRaw.isEmpty else { return nil }
            return IdDocumentType(rawValue: idDocumentTypeRaw)
        }
        set {
            idDocumentTypeRaw = newValue?.rawValue ?? ""
            updatedAt = Date()
        }
    }

    var hasIdDocumentPhoto: Bool {
        IdDocumentPhotoStore.load(employeeId: id) != nil
    }

    var faceDepthSignature: FaceDepthSignature? {
        get {
            guard !faceDepthSignatureData.isEmpty else { return nil }
            return try? EmbeddingCrypto.decryptDepthSignature(faceDepthSignatureData)
        }
        set {
            if let newValue {
                faceDepthSignatureData =
                    (try? EmbeddingCrypto.encryptDepthSignature(newValue)) ?? Data()
            } else {
                faceDepthSignatureData = Data()
            }
            updatedAt = Date()
            if syncStatus == .synced {
                syncStatus = .pending
            }
        }
    }
}
