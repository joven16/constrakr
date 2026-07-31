//
//  FaceEmbedding.swift
//  ConsTrac
//

import Foundation

/// Placeholder container for a face embedding vector produced by a Core ML model.
/// INTEGRATION: Replace `values` generation with output from your face recognition model.
struct FaceEmbedding: Codable, Equatable, Hashable {
    let pose: FacePose
    /// Fixed-length feature vector. Currently mock random values (128-dim).
    let values: [Float]
    let capturedAt: Date

    /// Preferred production dimension when AdaFace is loaded; otherwise handcrafted size.
    static var expectedDimension: Int {
        CoreMLFaceRecognizer.shared.isReady
            ? CoreMLFaceRecognizer.embeddingDimension
            : FaceImagePreprocessor.embeddingDimension
    }

    init(pose: FacePose, values: [Float], capturedAt: Date = Date()) {
        self.pose = pose
        self.values = FaceImagePreprocessor.l2Normalize(values)
        self.capturedAt = capturedAt
    }

    /// Test helper only — never used by scanner/enrollment production paths.
    static func placeholder(for pose: FacePose, seed: UInt64 = 0) -> FaceEmbedding {
        let poseSalt = UInt64(bitPattern: Int64(pose.rawValue.hashValue))
        var generator = SeededGenerator(seed: seed &+ poseSalt)
        let dim = expectedDimension
        let values = (0..<dim).map { _ in Float.random(in: -1...1, using: &generator) }
        return FaceEmbedding(pose: pose, values: values)
    }

    func cosineSimilarity(to other: FaceEmbedding) -> Float {
        FaceImagePreprocessor.cosineSimilarity(values, other.values)
    }
}

/// Simple seeded RNG so mock embeddings are reproducible across sessions.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
