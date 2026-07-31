//
//  EmbeddingCrypto.swift
//  ConsTrac
//
//  CHANGE: Face embeddings are encrypted at rest and before upload (AES-GCM via CryptoKit).
//  Raw camera frames are never written here.
//

import CryptoKit
import Foundation
import Security

enum EmbeddingCrypto {
    private static let keychainService = "com.constrac.embedding-crypto"
    private static let keychainAccount = "embedding-aes-key"

    enum CryptoError: LocalizedError {
        case keyGenerationFailed
        case encryptionFailed
        case decryptionFailed
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Could not create embedding encryption key."
            case .encryptionFailed: return "Failed to encrypt face embedding."
            case .decryptionFailed: return "Failed to decrypt face embedding."
            case .invalidPayload: return "Encrypted embedding payload is invalid."
            }
        }
    }

    /// Encrypts a single embedding vector for local storage / POST /face-embeddings.
    static func encryptValues(_ values: [Float]) throws -> Data {
        let plain = try JSONEncoder().encode(values)
        return try seal(plain)
    }

    static func decryptValues(_ ciphertext: Data) throws -> [Float] {
        let plain = try open(ciphertext)
        return try JSONDecoder().decode([Float].self, from: plain)
    }

    /// Encrypts the full enrollment set stored on `Employee.faceEmbeddingsData`.
    static func encryptEmbeddings(_ embeddings: [FaceEmbedding]) throws -> Data {
        let plain = try JSONEncoder().encode(embeddings)
        return try seal(plain)
    }

    static func decryptEmbeddings(_ ciphertext: Data) throws -> [FaceEmbedding] {
        let plain = try open(ciphertext)
        return try JSONDecoder().decode([FaceEmbedding].self, from: plain)
    }

    // MARK: - AES-GCM

    private static func seal(_ plain: Data) throws -> Data {
        let key = try symmetricKey()
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw CryptoError.encryptionFailed }
        return combined
    }

    private static func open(_ combined: Data) throws -> Data {
        let key = try symmetricKey()
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    private static func symmetricKey() throws -> SymmetricKey {
        if let existing = loadKeyData() {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try saveKeyData(data)
        return key
    }

    private static func loadKeyData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func saveKeyData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoError.keyGenerationFailed }
    }
}
