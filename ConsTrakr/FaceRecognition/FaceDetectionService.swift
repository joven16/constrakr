//
//  FaceDetectionService.swift
//  ConsTrakr
//

import Foundation
import Vision

/// Detects faces and landmarks using Apple Vision.
final class FaceDetectionService: @unchecked Sendable {
    private let sequenceHandler = VNSequenceRequestHandler()

    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [DetectedFace] {
        let request = VNDetectFaceLandmarksRequest()
        // CameraManager already rotates buffers to portrait (90°) and mirrors the front camera,
        // so Vision should treat frames as upright mirrored — not leftMirrored.
        // Wrong orientation flips yaw and breaks Look Left / Look Right enrollment.
        try sequenceHandler.perform([request], on: pixelBuffer, orientation: .upMirrored)

        guard let results = request.results, !results.isEmpty else { return [] }

        return results.map { observation in
            let pose = HeadPoseEstimator.estimate(from: observation)
            return DetectedFace(
                boundingBox: observation.boundingBox,
                confidence: observation.confidence,
                yaw: pose.yaw,
                pitch: pose.pitch,
                roll: pose.roll
            )
        }
    }

    func primaryFace(in pixelBuffer: CVPixelBuffer) throws -> DetectedFace? {
        try detectFaces(in: pixelBuffer)
            .filter { $0.confidence >= AppConstants.minFaceConfidence }
            .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
    }
}
