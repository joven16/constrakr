//
//  FaceDetectionService.swift
//  ConsTrakr
//

import AVFoundation
import Foundation
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
}
