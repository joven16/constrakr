//
//  FaceRecognitionPipeline.swift
//  ConsTrakr
//

import CoreVideo
import Foundation
import os

@MainActor
struct FaceRecognitionPipeline {
    let detectionService = FaceDetectionService()
    let embeddingService = FaceEmbeddingService()
    let matchingService = FaceMatchingService()
    private let logger = Logger(subsystem: "com.constrakr", category: "FacePipeline")

    enum PipelineError: LocalizedError {
        case noFaceDetected
        case unknownPerson(bestSimilarity: Float)
        case poorQuality(String)

        var errorDescription: String? {
            switch self {
            case .noFaceDetected: return "No face detected"
            case .unknownPerson: return "Unknown Person"
            case .poorQuality(let message): return message
            }
        }
    }

    func process(
        pixelBuffer: CVPixelBuffer,
        employees: [Employee],
        mirrored: Bool = true
    ) throws -> FaceMatchResult {
        // Work on a deep copy so a recycled camera buffer cannot leak prior-frame pixels.
        let frame = try FaceImagePreprocessor.copyPixelBuffer(pixelBuffer)

        guard let face = try detectionService.primaryFace(in: frame, mirrored: mirrored) else {
            throw PipelineError.noFaceDetected
        }

        let embedding: FaceEmbedding
        do {
            embedding = try embeddingService.generateEmbedding(
                from: frame,
                face: face,
                pose: face.estimatedPose
            )
        } catch let error as FaceImagePreprocessor.PreprocessError {
            throw PipelineError.poorQuality(error.localizedDescription)
        }

        let (match, diagnostics) = matchingService.match(probe: embedding, against: employees)
        guard let match else {
            logger.info("Unknown Person best=\(diagnostics.bestSimilarity)")
            throw PipelineError.unknownPerson(bestSimilarity: diagnostics.bestSimilarity)
        }
        return match
    }
}
