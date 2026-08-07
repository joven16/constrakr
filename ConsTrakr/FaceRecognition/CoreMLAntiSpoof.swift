//
//  CoreMLAntiSpoof.swift
//  ConsTrakr
//
//  MiniFASNetV2 — on-device screen / photo / replay detection (Silent Face Anti-Spoofing).
//  Model: FaceRecognition/Models/MiniFASNetV2.mlpackage
//  Input: BGR face crop 80×80 float NCHW · Output: 2-class logits (0=fake, 1=live)
//

import CoreML
import CoreVideo
import Foundation
import os

struct AntiSpoofVerdict: Sendable {
    let isLive: Bool
    let liveScore: Float
    let spoofScore: Float
}

/// Tracks consecutive AI spoof hits so one noisy frame does not restart the scan.
final class AntiSpoofTracker {
    private var spoofStreak = 0
    private let rejectAfter: Int

    init(rejectAfter: Int = 3) {
        self.rejectAfter = rejectAfter
    }

    func reset() {
        spoofStreak = 0
    }

    /// Returns true when the face should be treated as a presentation attack.
    func observe(liveScore: Float, liveThreshold: Float = 0.72) -> Bool {
        if liveScore < liveThreshold {
            spoofStreak += 1
        } else {
            spoofStreak = max(0, spoofStreak - 2)
        }
        return spoofStreak >= rejectAfter
    }
}

final class CoreMLAntiSpoof: @unchecked Sendable {
    static let shared = CoreMLAntiSpoof()

    static let inputSize = 80
    static let cropScale: CGFloat = 2.7
    /// Minimum softmax probability for the “live” class.
    static let liveThreshold: Float = 0.72

    private let logger = Logger(subsystem: "com.constrakr", category: "AntiSpoof")
    private let model: MLModel?
    private(set) var isReady = false
    private(set) var loadError: String?

    private init() {
        do {
            let compiled = try Self.loadModel()
            self.model = compiled
            self.isReady = true
            logger.info("MiniFASNetV2 anti-spoof loaded")
            #if DEBUG
            print("[ConsTrakr] Anti-spoof: MiniFASNetV2 Core ML READY")
            #endif
        } catch {
            self.model = nil
            self.isReady = false
            self.loadError = error.localizedDescription
            logger.error("MiniFASNetV2 failed to load: \(error.localizedDescription)")
            #if DEBUG
            print("[ConsTrakr] Anti-spoof: MiniFASNetV2 NOT loaded — \(error.localizedDescription)")
            #endif
        }
    }

    func classify(pixelBuffer: CVPixelBuffer, boundingBox: CGRect) throws -> AntiSpoofVerdict {
        guard let model else {
            throw AntiSpoofError.modelNotLoaded
        }

        let input = try Self.makeInput(from: pixelBuffer, boundingBox: boundingBox)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(multiArray: input)
        ])
        let output = try model.prediction(from: provider)
        guard let logits = output.featureValue(for: "output")?.multiArrayValue else {
            throw AntiSpoofError.missingOutput
        }

        let fakeLogit = Float(truncating: logits[[0, 0] as [NSNumber]])
        let liveLogit = Float(truncating: logits[[0, 1] as [NSNumber]])
        let probs = Self.softmax([fakeLogit, liveLogit])
        let spoofScore = probs[0]
        let liveScore = probs[1]
        return AntiSpoofVerdict(
            isLive: liveScore >= Self.liveThreshold,
            liveScore: liveScore,
            spoofScore: spoofScore
        )
    }

    // MARK: - Preprocess (matches Silent-Face-Anti-Spoofing crop + NCHW BGR float)

    private static func makeInput(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) throws -> MLMultiArray {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw AntiSpoofError.unsupportedFormat
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelRect = visionBoxToPixelRect(boundingBox, width: width, height: height)

        let x = pixelRect.minX
        let y = pixelRect.minY
        let boxW = pixelRect.width
        let boxH = pixelRect.height
        let scaleFactor = min(
            (CGFloat(height) - 1) / max(boxH, 1),
            (CGFloat(width) - 1) / max(boxW, 1),
            cropScale
        )
        let newW = boxW * scaleFactor
        let newH = boxH * scaleFactor
        let centerX = x + boxW / 2
        let centerY = y + boxH / 2
        let x1 = max(0, Int(centerX - newW / 2))
        let y1 = max(0, Int(centerY - newH / 2))
        let x2 = min(width - 1, Int(centerX + newW / 2))
        let y2 = min(height - 1, Int(centerY + newH / 2))
        guard x2 > x1, y2 > y1 else { throw AntiSpoofError.invalidCrop }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw AntiSpoofError.invalidCrop
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)], dataType: .float32)
        let cropW = x2 - x1 + 1
        let cropH = y2 - y1 + 1

        for outY in 0..<inputSize {
            let srcY = y1 + outY * cropH / inputSize
            let row = base.advanced(by: srcY * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for outX in 0..<inputSize {
                let srcX = x1 + outX * cropW / inputSize
                let pixel = row.advanced(by: srcX * 4)
                let b = Float(pixel[0])
                let g = Float(pixel[1])
                let r = Float(pixel[2])
                array[[0, 0, outY, outX] as [NSNumber]] = NSNumber(value: b)
                array[[0, 1, outY, outX] as [NSNumber]] = NSNumber(value: g)
                array[[0, 2, outY, outX] as [NSNumber]] = NSNumber(value: r)
            }
        }
        return array
    }

    private static func visionBoxToPixelRect(_ box: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(
            x: box.minX * CGFloat(width),
            y: (1 - box.maxY) * CGFloat(height),
            width: box.width * CGFloat(width),
            height: box.height * CGFloat(height)
        )
    }

    private static func softmax(_ logits: [Float]) -> [Float] {
        guard let maxLogit = logits.max() else { return logits }
        let exps = logits.map { expf($0 - maxLogit) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return logits.map { _ in 1 / Float(logits.count) } }
        return exps.map { $0 / sum }
    }

    private static func loadModel() throws -> MLModel {
        if let url = Bundle.main.url(forResource: "MiniFASNetV2", withExtension: "mlmodelc") {
            return try MLModel(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "MiniFASNetV2", withExtension: "mlpackage") {
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled)
        }
        throw AntiSpoofError.modelNotFound
    }

    enum AntiSpoofError: LocalizedError {
        case modelNotFound
        case modelNotLoaded
        case missingOutput
        case invalidCrop
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "MiniFASNetV2 model not found in app bundle."
            case .modelNotLoaded: return "MiniFASNetV2 anti-spoof model is not loaded."
            case .missingOutput: return "MiniFASNetV2 did not return logits."
            case .invalidCrop: return "Could not crop face for anti-spoof check."
            case .unsupportedFormat: return "Unsupported pixel format for anti-spoof."
            }
        }
    }
}
