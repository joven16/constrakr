//
//  FaceDetectionService.swift
//  ConsTrakr
//

import AVFoundation
import Foundation
import UIKit
import Vision

/// Detects faces and landmarks using Apple Vision.
final class FaceDetectionService: @unchecked Sendable {
    private let sequenceHandler = VNSequenceRequestHandler()

    func detectFaces(
        in pixelBuffer: CVPixelBuffer,
        mirrored: Bool = true
    ) throws -> [DetectedFace] {
        let request = VNDetectFaceLandmarksRequest()
        // Front camera frames are mirrored; back camera frames are not.
        let orientation: CGImagePropertyOrientation = mirrored ? .upMirrored : .up
        try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)

        guard let results = request.results, !results.isEmpty else { return [] }

        return results.map { observation in
            let pose = HeadPoseEstimator.estimate(from: observation)
            let leftEAR = LivenessMetrics.eyeAspectRatio(
                points: observation.landmarks?.leftEye?.normalizedPoints ?? []
            )
            let rightEAR = LivenessMetrics.eyeAspectRatio(
                points: observation.landmarks?.rightEye?.normalizedPoints ?? []
            )
            return DetectedFace(
                boundingBox: observation.boundingBox,
                confidence: observation.confidence,
                yaw: pose.yaw,
                pitch: pose.pitch,
                roll: pose.roll,
                leftEyeEAR: leftEAR,
                rightEyeEAR: rightEAR
            )
        }
    }

    func primaryFace(
        in pixelBuffer: CVPixelBuffer,
        mirrored: Bool = true
    ) throws -> DetectedFace? {
        try detectFaces(in: pixelBuffer, mirrored: mirrored)
            .filter { $0.confidence >= AppConstants.minFaceConfidence }
            .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
    }

    /// Detects the largest face in a stored enrollment JPEG (Android full frame or iOS face crop).
    func primaryFace(inEnrollmentJPEG data: Data) throws -> DetectedFace? {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else { return nil }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        try handler.perform([request])

        guard let results = request.results, !results.isEmpty else { return nil }

        let faces = results.map { observation -> DetectedFace in
            let pose = HeadPoseEstimator.estimate(from: observation)
            return DetectedFace(
                boundingBox: observation.boundingBox,
                confidence: observation.confidence,
                yaw: pose.yaw,
                pitch: pose.pitch,
                roll: pose.roll,
                leftEyeEAR: LivenessMetrics.eyeAspectRatio(
                    points: observation.landmarks?.leftEye?.normalizedPoints ?? []
                ),
                rightEyeEAR: LivenessMetrics.eyeAspectRatio(
                    points: observation.landmarks?.rightEye?.normalizedPoints ?? []
                )
            )
        }

        return faces
            .filter { $0.confidence >= AppConstants.minFaceConfidence }
            .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
