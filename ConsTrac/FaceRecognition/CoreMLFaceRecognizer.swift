//
//  CoreMLFaceRecognizer.swift
//  ConsTrac
//
//  AdaFace IR-18 (512-d) — real on-device face recognition embeddings.
// Model: FaceRecognition/Models/AdaFace_IR18.mlpackage
// Input: face_image 112×112 · Output: embedding 512-d (L2-normalize before compare)
//

import CoreML
import CoreVideo
import Foundation
import os

final class CoreMLFaceRecognizer: @unchecked Sendable {
    static let shared = CoreMLFaceRecognizer()

    static let inputSize = 112
    static let embeddingDimension = 512

    private let logger = Logger(subsystem: "com.constrac", category: "AdaFace")
    private let model: MLModel?
    private(set) var isReady = false
    private(set) var loadError: String?

    private init() {
        do {
            let compiled = try Self.loadModel()
            self.model = compiled
            self.isReady = true
            logger.info("AdaFace IR-18 loaded (512-d face embeddings)")
            #if DEBUG
            print("[ConsTrac] Face engine: AdaFace IR-18 Core ML READY")
            #endif
        } catch {
            self.model = nil
            self.isReady = false
            self.loadError = error.localizedDescription
            logger.error("AdaFace failed to load: \(error.localizedDescription)")
            #if DEBUG
            print("[ConsTrac] Face engine: AdaFace NOT loaded — \(error.localizedDescription)")
            #endif
        }
    }

    /// Crops the Vision face box from the frame and returns a 512-d L2-normalized embedding.
    func embed(pixelBuffer: CVPixelBuffer, boundingBox: CGRect) throws -> [Float] {
        guard let model else {
            throw FaceImagePreprocessor.PreprocessError.lockFailed
        }

        let faceBuffer = try FaceImagePreprocessor.makeSquareFacePixelBuffer(
            from: pixelBuffer,
            boundingBox: boundingBox,
            outputSize: Self.inputSize
        )

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "face_image": MLFeatureValue(pixelBuffer: faceBuffer)
        ])
        let output = try model.prediction(from: input)

        guard let multiArray = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbeddingError.missingOutput
        }

        var values = [Float](repeating: 0, count: multiArray.count)
        for i in 0..<multiArray.count {
            values[i] = Float(truncating: multiArray[i])
        }
        return FaceImagePreprocessor.l2Normalize(values)
    }

    private static func loadModel() throws -> MLModel {
        // Prefer compiled model in the app bundle (Xcode compiles .mlpackage automatically).
        if let url = Bundle.main.url(forResource: "AdaFace_IR18", withExtension: "mlmodelc") {
            return try MLModel(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "AdaFace_IR18", withExtension: "mlpackage") {
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled)
        }
        // Dev fallback: load from the Models folder next to the source tree (simulator/debug).
        let fm = FileManager.default
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("AdaFace_IR18.mlpackage"),
            Bundle.main.resourceURL?.appendingPathComponent("AdaFace_IR18.mlpackage")
        ].compactMap { $0 }
        for url in candidates where fm.fileExists(atPath: url.path) {
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled)
        }
        throw EmbeddingError.modelNotFound
    }

    enum EmbeddingError: LocalizedError {
        case modelNotFound
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "AdaFace_IR18 model not found in app bundle."
            case .missingOutput: return "AdaFace model did not return an embedding."
            }
        }
    }
}
