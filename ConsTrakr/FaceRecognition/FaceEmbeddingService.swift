//
//  FaceEmbeddingService.swift
//  ConsTrakr
//
//  Prefers AdaFace IR-18 Core ML (512-d). Falls back to handcrafted features only
//  if the model is missing from the bundle.
//

import CoreVideo
import Foundation
import os

final class FaceEmbeddingService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.constrakr", category: "FaceEmbedding")

    var usesCoreML: Bool { CoreMLFaceRecognizer.shared.isReady }

    func generateEmbedding(
        from pixelBuffer: CVPixelBuffer,
        face: DetectedFace,
        pose: FacePose
    ) throws -> FaceEmbedding {
        if CoreMLFaceRecognizer.shared.isReady {
            do {
                let values = try CoreMLFaceRecognizer.shared.embed(
                    pixelBuffer: pixelBuffer,
                    boundingBox: face.boundingBox
                )
                let embedding = FaceEmbedding(pose: pose, values: values)
                let norm = FaceImagePreprocessor.l2Norm(values)
                logger.info("AdaFace embedding len=\(values.count) norm=\(norm)")
                #if DEBUG
                print("[ConsTrakr][Embedding] engine=AdaFace len=\(values.count) norm=\(String(format: "%.4f", norm))")
                #endif
                return embedding
            } catch {
                logger.error("AdaFace inference failed, falling back: \(error.localizedDescription)")
            }
        }

        // Fallback (weaker): handcrafted content embedding — not true biometrics.
        let prepared = try FaceImagePreprocessor.prepare(
            pixelBuffer: pixelBuffer,
            boundingBox: face.boundingBox
        )
        let values = FaceImagePreprocessor.makeContentEmbedding(from: prepared)
        #if DEBUG
        print("[ConsTrakr][Embedding] engine=HandcraftedFallback len=\(values.count)")
        #endif
        return FaceEmbedding(pose: pose, values: values)
    }
}
