//
//  IdDocumentPhotoStore.swift
//  ConsTrakr
//
//  Persists the primary government ID JPEG captured during registration.
//

import Foundation
import UIKit

enum IdDocumentPhotoStore {
    private static let folderName = "IdDocumentPhotos"
    private static let jpegQuality: CGFloat = 0.82

    static func saveJPEG(_ data: Data, employeeId: UUID) throws {
        let dir = directory(for: employeeId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL(employeeId: employeeId), options: .completeFileProtection)
    }

    static func saveUIImage(_ image: UIImage, employeeId: UUID) throws {
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw StoreError.encodingFailed
        }
        try saveJPEG(data, employeeId: employeeId)
    }

    static func load(employeeId: UUID) -> Data? {
        try? Data(contentsOf: fileURL(employeeId: employeeId))
    }

    static func delete(employeeId: UUID) {
        try? FileManager.default.removeItem(at: fileURL(employeeId: employeeId))
        try? FileManager.default.removeItem(at: directory(for: employeeId))
    }

    static func deleteAll() {
        let root = rootDirectory()
        try? FileManager.default.removeItem(at: root)
    }

    private static func rootDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func directory(for employeeId: UUID) -> URL {
        rootDirectory().appendingPathComponent(employeeId.uuidString, isDirectory: true)
    }

    private static func fileURL(employeeId: UUID) -> URL {
        directory(for: employeeId).appendingPathComponent("primary.jpg")
    }

    enum StoreError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Could not encode the ID photo."
            }
        }
    }
}
