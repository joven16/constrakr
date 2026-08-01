//
//  FaceDepthSignature.swift
//  ConsTrakr
//
// Compact TrueDepth face geometry for enrollment + anti-spoof checks.
// A laptop/phone screen cannot produce a stable nose/cheek depth grid.
//

import AVFoundation
import CoreVideo
import Foundation

struct FaceDepthSignature: Codable, Equatable {
    /// Row-major 8×8 relative depths (median-centered; closer = higher).
    let grid: [Float]
    let depthRangeMeters: Float
    let planeResidualMeters: Float
    let noseProminenceMeters: Float
    let capturedAt: Date

    static let gridSize = 8
    static let cellCount = gridSize * gridSize
    /// Frames needed to lock a stable enrollment scan.
    static let enrollmentFrameTarget = 10

    var isValid: Bool {
        grid.count == Self.cellCount
            && depthRangeMeters >= 0.012
            && planeResidualMeters >= 0.0022
    }

    /// Build a signature from the current TrueDepth map and Vision face box.
    static func extract(depthData: AVDepthData, faceBox: CGRect, strict: Bool = false) -> FaceDepthSignature? {
        let flat = DepthFlatnessDetector.evaluate(
            depthData: depthData,
            faceBox: faceBox,
            strict: strict
        )
        guard !flat.isFlat else { return nil }

        let converted: AVDepthData
        if depthData.depthDataType == kCVPixelFormatType_DepthFloat32 {
            converted = depthData
        } else {
            converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }

        let map = converted.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)

        let insetBox = faceBox.insetBy(dx: faceBox.width * 0.18, dy: faceBox.height * 0.20)
        let rect = CGRect(
            x: insetBox.minX * CGFloat(width),
            y: (1 - insetBox.maxY) * CGFloat(height),
            width: insetBox.width * CGFloat(width),
            height: insetBox.height * CGFloat(height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard rect.width > 8, rect.height > 8 else { return nil }

        var raw = [Float](repeating: 0, count: cellCount)
        var counts = [Int](repeating: 0, count: cellCount)
        let cellW = Float(rect.width) / Float(gridSize)
        let cellH = Float(rect.height) / Float(gridSize)
        let step = max(1, Int(min(cellW, cellH) / 2))

        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: step) {
                let d = row[x]
                // Allow closer faces after "move closer" (was 0.18 — dropped near-camera depth).
                guard d.isFinite, d > 0.12, d < 1.4 else { continue }
                let cx = min(gridSize - 1, Int(Float(x - Int(rect.minX)) / cellW))
                let cy = min(gridSize - 1, Int(Float(y - Int(rect.minY)) / cellH))
                let idx = cy * gridSize + cx
                raw[idx] += d
                counts[idx] += 1
            }
        }

        let filled = counts.filter { $0 >= 1 }.count
        // Do not require every cell — edges often miss when the face is slightly off-center.
        guard filled >= Int(Double(cellCount) * 0.55) else { return nil }

        var means = [Float](repeating: 0, count: cellCount)
        var known: [Float] = []
        for i in 0..<cellCount {
            if counts[i] >= 1 {
                let m = raw[i] / Float(counts[i])
                means[i] = m
                known.append(m)
            }
        }
        guard known.count >= 8 else { return nil }
        let sortedKnown = known.sorted()
        let fillValue = sortedKnown[sortedKnown.count / 2]
        for i in 0..<cellCount where counts[i] == 0 {
            means[i] = fillValue
        }

        let sorted = means.sorted()
        let median = sorted[sorted.count / 2]
        // Relative relief: nose closer than cheeks → positive center.
        let relative = means.map { median - $0 }
        let normalized = FaceImagePreprocessor.l2Normalize(relative)

        return FaceDepthSignature(
            grid: normalized,
            depthRangeMeters: flat.depthRangeMeters,
            planeResidualMeters: flat.planeResidualMeters,
            noseProminenceMeters: flat.noseProminenceMeters,
            capturedAt: Date()
        )
    }

    func cosineSimilarity(to other: FaceDepthSignature) -> Float {
        guard grid.count == other.grid.count else { return 0 }
        return FaceImagePreprocessor.cosineSimilarity(grid, other.grid)
    }

    /// Average several valid scans into one enrollment template.
    static func average(_ signatures: [FaceDepthSignature]) -> FaceDepthSignature? {
        guard let first = signatures.first, !signatures.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: cellCount)
        var range: Float = 0
        var residual: Float = 0
        var nose: Float = 0
        for s in signatures {
            guard s.grid.count == cellCount else { continue }
            for i in 0..<cellCount { sum[i] += s.grid[i] }
            range += s.depthRangeMeters
            residual += s.planeResidualMeters
            nose += s.noseProminenceMeters
        }
        let n = Float(signatures.count)
        let averaged = FaceImagePreprocessor.l2Normalize(sum.map { $0 / n })
        return FaceDepthSignature(
            grid: averaged,
            depthRangeMeters: range / n,
            planeResidualMeters: residual / n,
            noseProminenceMeters: nose / n,
            capturedAt: first.capturedAt
        )
    }
}

/// Accumulates TrueDepth frames until a stable enrollment signature is ready.
struct FaceDepthScanAccumulator {
    private(set) var samples: [FaceDepthSignature] = []
    private(set) var lastRejectReason: String?

    var progress: Double {
        min(1, Double(samples.count) / Double(FaceDepthSignature.enrollmentFrameTarget))
    }

    var isComplete: Bool {
        samples.count >= FaceDepthSignature.enrollmentFrameTarget
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        lastRejectReason = nil
    }

    mutating func observe(depthData: AVDepthData?, faceBox: CGRect) -> FaceDepthSignature? {
        guard let depthData else {
            lastRejectReason = "Hold still — waiting for 3D depth…"
            return nil
        }

        let flat = DepthFlatnessDetector.evaluate(
            depthData: depthData,
            faceBox: faceBox,
            strict: false
        )
        if flat.isFlat {
            // Pause progress quietly — do not accuse a live user of using a screen.
            lastRejectReason = nil
            return nil
        }

        guard let signature = FaceDepthSignature.extract(
            depthData: depthData,
            faceBox: faceBox,
            strict: false
        ) else {
            lastRejectReason = nil
            return nil
        }

        lastRejectReason = nil
        samples.append(signature)
        guard isComplete else { return nil }
        return FaceDepthSignature.average(samples)
    }
}
