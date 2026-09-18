//
//  EnrollmentPhotoReembedder.swift
//  ConsTrakr
//
//  Rebuilds AdaFace templates from synced enrollment JPEGs when remote embeddings
//  were encrypted on another device (e.g. Android → iOS migration).
//

import CoreGraphics
import Foundation
import SwiftData
import UIKit

@MainActor
enum EnrollmentPhotoReembedder {
    private static let faceDetector = FaceDetectionService()
    private static let embeddingService = FaceEmbeddingService()

    enum ReembedError: LocalizedError {
        case modelUnavailable
        case noFaceDetected

        var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                return "AdaFace model is not loaded on this device."
            case .noFaceDetected:
                return "No face detected in enrollment photo."
            }
        }
    }

    /// Scans all synced employees and rebuilds missing/unreadable AdaFace templates from JPEGs.
    @discardableResult
    static func reembedAllIfNeeded(context: ModelContext, api: APIService? = nil) async throws -> Int {
        guard CoreMLFaceRecognizer.shared.isReady else { return 0 }

        let empRepo = EmployeeRepository(context: context)
        let photoRepo = FaceEnrollmentPhotoRepository(context: context)
        var total = 0

        for employee in try empRepo.fetchAll() {
            guard APIDecoding.normalizedServerId(employee.serverId) != nil else { continue }
            total += try await reembedEmployeeIfNeeded(
                employee,
                context: context,
                api: api,
                photoRepo: photoRepo,
                empRepo: empRepo
            )
        }

        if total > 0 {
            try context.save()
            NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
        }
        return total
    }

    @discardableResult
    static func reembedEmployeeIfNeeded(
        _ employee: Employee,
        context: ModelContext,
        api: APIService? = nil,
        photoRepo: FaceEnrollmentPhotoRepository? = nil,
        empRepo: EmployeeRepository? = nil
    ) async throws -> Int {
        guard CoreMLFaceRecognizer.shared.isReady else { return 0 }
        guard APIDecoding.normalizedServerId(employee.serverId) != nil else { return 0 }

        let photoRepo = photoRepo ?? FaceEnrollmentPhotoRepository(context: context)
        let empRepo = empRepo ?? EmployeeRepository(context: context)

        if EnrollmentPhotoStore.loadAll(employeeId: employee.id).isEmpty,
           let api,
           let serverId = APIDecoding.normalizedServerId(employee.serverId) {
            let remotePhotos = try await api.getFaceEnrollmentPhotos(
                employeeServerId: serverId,
                includeMedia: true
            )
            for dto in remotePhotos {
                try photoRepo.upsertFromRemote(dto, employeeLocalId: employee.id)
            }
        }

        let photos = EnrollmentPhotoStore.loadAll(employeeId: employee.id)
        guard !photos.isEmpty else { return 0 }

        let embRepo = FaceEmbeddingRepository(context: context)
        var working = usableEmbeddings(for: employee, embRepo: embRepo)
        let photoPoses = Set(photos.map(\.pose))
        let missingPoses = photoPoses.subtracting(working.keys)
        guard !missingPoses.isEmpty else { return 0 }

        var rebuilt = working
        var count = 0
        for (pose, jpeg) in photos where missingPoses.contains(pose) {
            guard let embedding = try? embedFromEnrollmentJPEG(jpeg, pose: pose) else { continue }
            rebuilt[pose] = embedding
            count += 1
        }

        guard count > 0 else { return 0 }

        let merged = FacePose.enrollmentOrder.compactMap { rebuilt[$0] }
        guard !merged.isEmpty else { return 0 }

        try embRepo.replaceLocalEmbeddings(
            for: employee,
            embeddings: merged,
            employeeServerId: employee.serverId
        )
        employee.faceEmbeddings = merged
        employee.syncStatus = .pending
        try empRepo.update(employee, persist: false)
        return count
    }

    private static func usableEmbeddings(
        for employee: Employee,
        embRepo: FaceEmbeddingRepository
    ) -> [FacePose: FaceEmbedding] {
        let expectedDim = FaceEmbedding.expectedDimension
        var map: [FacePose: FaceEmbedding] = [:]

        if let entities = try? embRepo.fetch(forEmployeeLocalId: employee.id) {
            for entity in entities {
                guard let embedding = try? entity.decryptedEmbedding(),
                      embedding.values.count == expectedDim else { continue }
                map[embedding.pose] = embedding
            }
        }

        if map.isEmpty {
            for embedding in employee.faceEmbeddings where embedding.values.count == expectedDim {
                map[embedding.pose] = embedding
            }
        }

        return map
    }

    private static func embedFromEnrollmentJPEG(_ jpeg: Data, pose: FacePose) throws -> FaceEmbedding {
        guard CoreMLFaceRecognizer.shared.isReady else { throw ReembedError.modelUnavailable }

        let buffer = try PixelBufferConverter.pixelBuffer(fromJPEG: jpeg)
        let face: DetectedFace
        if let detected = try faceDetector.primaryFace(inEnrollmentJPEG: jpeg) {
            face = detected
        } else if isLikelyFaceCrop(jpeg) {
            face = DetectedFace(
                boundingBox: CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84),
                confidence: 1,
                yaw: 0,
                pitch: 0,
                roll: 0,
                leftEyeEAR: nil,
                rightEyeEAR: nil
            )
        } else {
            throw ReembedError.noFaceDetected
        }

        let embedding = try embeddingService.generateEmbedding(
            from: buffer,
            face: face,
            pose: pose
        )
        guard embeddingService.usesCoreML,
              embedding.values.count == CoreMLFaceRecognizer.embeddingDimension else {
            throw ReembedError.modelUnavailable
        }
        return embedding
    }

    private static func isLikelyFaceCrop(_ jpeg: Data) -> Bool {
        guard let image = UIImage(data: jpeg) else { return false }
        let width = image.size.width
        let height = image.size.height
        guard width >= 80, height >= 80 else { return false }
        let ratio = width / height
        return ratio > 0.75 && ratio < 1.33
    }
}
