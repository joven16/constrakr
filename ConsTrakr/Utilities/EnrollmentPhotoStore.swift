//
//  EnrollmentPhotoStore.swift
//  ConsTrakr
//
//  Persists JPEG face crops captured during registration for employee detail review.
//

import CoreVideo
import Foundation
import UIKit

enum EnrollmentPhotoStore {
    private static let folderName = "EnrollmentPhotos"
    private static let jpegQuality: CGFloat = 0.72
    private static let cropSize = 224

    static func encodeFaceJPEG(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) -> Data? {
        guard let square = try? FaceImagePreprocessor.makeSquareFacePixelBuffer(
            from: pixelBuffer,
            boundingBox: boundingBox,
            outputSize: cropSize
        ) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: square)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality)
    }

    static func saveAll(
        employeeId: UUID,
        photos: [FacePose: Data]
    ) throws {
        let dir = directory(for: employeeId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (pose, data) in photos {
            try data.write(to: fileURL(employeeId: employeeId, pose: pose), options: .completeFileProtection)
        }
    }

    static func load(employeeId: UUID, pose: FacePose) -> Data? {
        try? Data(contentsOf: fileURL(employeeId: employeeId, pose: pose))
    }

    static func loadAll(employeeId: UUID) -> [(pose: FacePose, data: Data)] {
        FacePose.allCases.compactMap { pose in
            guard let data = load(employeeId: employeeId, pose: pose) else { return nil }
            return (pose, data)
        }
    }

    static func delete(employeeId: UUID) {
        let dir = directory(for: employeeId)
        try? FileManager.default.removeItem(at: dir)
    }

    private static func rootDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func directory(for employeeId: UUID) -> URL {
        rootDirectory().appendingPathComponent(employeeId.uuidString, isDirectory: true)
    }

    private static func fileURL(employeeId: UUID, pose: FacePose) -> URL {
        directory(for: employeeId).appendingPathComponent("\(pose.rawValue).jpg")
    }
}
