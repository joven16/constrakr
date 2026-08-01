//
//  DepthFlatnessDetector.swift
//  ConsTrakr
//
// Uses TrueDepth to reject flat presentation attacks (phone/laptop screens).
// A real face has centimeters of nose/cheek relief. A screen is nearly planar
// and often returns sparse / invalid IR depth.
//

import AVFoundation
import CoreVideo
import Foundation

enum DepthFlatnessDetector {
    struct Verdict {
        let isFlat: Bool
        let depthRangeMeters: Float
        let planeResidualMeters: Float
        let noseProminenceMeters: Float
        let validDepthRatio: Float
        let reason: String?
    }

    private struct Sample {
        let x: Float
        let y: Float
        let z: Float
    }

    /// Analyze depth inside the Vision face box.
    /// `faceBox` is Vision-normalized (origin bottom-left).
    /// Use `strict: false` after liveness passed so live matching is not blocked by pose/distance noise.
    static func evaluate(depthData: AVDepthData, faceBox: CGRect, strict: Bool = true) -> Verdict {
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
        guard let base = CVPixelBufferGetBaseAddress(map) else {
            return reject("No 3D face depth — screens and photos are blocked.")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)

        // Very tight crop: laptop bezels / desk edges behind a screen fake "3D range".
        let insetX = strict ? 0.32 : 0.26
        let insetY = strict ? 0.34 : 0.28
        let insetBox = faceBox.insetBy(dx: faceBox.width * insetX, dy: faceBox.height * insetY)
        let rect = CGRect(
            x: insetBox.minX * CGFloat(width),
            y: (1 - insetBox.maxY) * CGFloat(height),
            width: insetBox.width * CGFloat(width),
            height: insetBox.height * CGFloat(height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard rect.width > 6, rect.height > 6 else {
            return reject("No 3D face depth — screens and photos are blocked.")
        }

        var samples: [Sample] = []
        samples.reserveCapacity(256)
        var probed = 0
        var valid = 0
        let stepX = max(1, Int(rect.width) / 20)
        let stepY = max(1, Int(rect.height) / 20)

        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: stepY) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: stepX) {
                probed += 1
                let d = row[x]
                // Face distance window. Allow closer faces in enrollment / post-liveness checks.
                let minD: Float = strict ? 0.15 : 0.11
                let maxD: Float = strict ? 1.15 : 1.3
                if d.isFinite, d > minD, d < maxD {
                    valid += 1
                    samples.append(Sample(x: Float(x), y: Float(y), z: d))
                }
            }
        }

        let validRatio = probed > 0 ? Float(valid) / Float(probed) : 0

        // Enrollment / matching: only reject obvious screens — live faces vary a lot in IR noise.
        if !strict {
            return evaluateLenient(
                samples: samples,
                validRatio: validRatio,
                rect: rect
            )
        }

        let minValidRatio: Float = 0.38
        let minSamples = 28

        // Phone/laptop LCDs usually fail IR → sparse valid depth inside the face box.
        guard validRatio >= minValidRatio, samples.count >= minSamples else {
            return reject(
                "No 3D face depth — screens and photos are blocked.",
                validRatio: validRatio
            )
        }

        let depths = samples.map(\.z).sorted()
        let lo = depths[depths.count / 10]
        let hi = depths[(depths.count * 9) / 10]
        let range = hi - lo
        let mean = depths.reduce(0, +) / Float(depths.count)

        // Mixed geometry (screen face + wall/desk behind) looks like huge depth spread.
        if range > 0.14 {
            return reject(
                "Unclear 3D depth (possible screen). Hold a live face closer.",
                range: range,
                validRatio: validRatio
            )
        }

        // Real faces usually show ~2–6+ cm relief.
        if range < 0.020 {
            return reject(
                "Flat surface detected (screen/photo). Use a live person.",
                range: range,
                validRatio: validRatio
            )
        }

        let residual = planeResidual(samples)
        if residual < 0.0045 {
            return reject(
                "Flat surface detected (screen/photo). Use a live person.",
                range: range,
                residual: residual,
                validRatio: validRatio
            )
        }

        let nose = noseProminence(samples: samples, rect: rect)
        let minNose: Float = 0.005
        if nose >= 0, nose < minNose {
            return reject(
                "Face depth shape looks flat (possible screen or mask).",
                range: range,
                residual: residual,
                nose: nose,
                validRatio: validRatio
            )
        }

        // Face should sit at a plausible distance; allow closer after “move closer”.
        if mean < 0.10 || mean > 1.15 {
            return reject(
                "Hold your face at arm’s length for 3D check.",
                range: range,
                residual: residual,
                nose: nose,
                validRatio: validRatio
            )
        }

        return Verdict(
            isFlat: false,
            depthRangeMeters: range,
            planeResidualMeters: residual,
            noseProminenceMeters: nose,
            validDepthRatio: validRatio,
            reason: nil
        )
    }

    /// Lenient path for enrollment + identity matching — avoids false “screen” on live faces.
    private static func evaluateLenient(
        samples: [Sample],
        validRatio: Float,
        rect: CGRect
    ) -> Verdict {
        // LCD / photo replay: almost no usable IR depth in the face box.
        if validRatio < 0.16 || samples.count < 10 {
            return reject(
                "Hold still — waiting for 3D depth…",
                validRatio: validRatio
            )
        }

        let depths = samples.map(\.z).sorted()
        let lo = depths[depths.count / 10]
        let hi = depths[(depths.count * 9) / 10]
        let range = hi - lo
        let residual = planeResidual(samples)
        let nose = noseProminence(samples: samples, rect: rect)

        // Obvious flat plane (typical screen) — require BOTH very flat range and plane fit.
        if range < 0.011 && residual < 0.0022 {
            return reject(
                "Flat surface detected (screen/photo). Use a live person.",
                range: range,
                residual: residual,
                nose: nose,
                validRatio: validRatio
            )
        }

        // Noisy IR on some screens still looks slightly curved — reject weak nose relief.
        if nose >= 0, nose < 0.004, range < 0.022 {
            return reject(
                "Face depth shape looks flat (possible screen).",
                range: range,
                residual: residual,
                nose: nose,
                validRatio: validRatio
            )
        }

        return Verdict(
            isFlat: false,
            depthRangeMeters: range,
            planeResidualMeters: residual,
            noseProminenceMeters: nose,
            validDepthRatio: validRatio,
            reason: nil
        )
    }

    private static func reject(
        _ reason: String,
        range: Float = 0,
        residual: Float = 0,
        nose: Float = 0,
        validRatio: Float = 0
    ) -> Verdict {
        Verdict(
            isFlat: true,
            depthRangeMeters: range,
            planeResidualMeters: residual,
            noseProminenceMeters: nose,
            validDepthRatio: validRatio,
            reason: reason
        )
    }

    /// RMS residual of depth samples to a fitted plane z ≈ ax + by + c.
    private static func planeResidual(_ samples: [Sample]) -> Float {
        let n = Float(samples.count)
        guard n > 8 else { return 0 }

        var sumX: Float = 0, sumY: Float = 0, sumZ: Float = 0
        var sumXX: Float = 0, sumYY: Float = 0, sumXY: Float = 0
        var sumXZ: Float = 0, sumYZ: Float = 0
        for s in samples {
            sumX += s.x; sumY += s.y; sumZ += s.z
            sumXX += s.x * s.x; sumYY += s.y * s.y; sumXY += s.x * s.y
            sumXZ += s.x * s.z; sumYZ += s.y * s.z
        }

        let a11 = sumXX, a12 = sumXY, a13 = sumX
        let a21 = sumXY, a22 = sumYY, a23 = sumY
        let a31 = sumX, a32 = sumY, a33 = n
        let b1 = sumXZ, b2 = sumYZ, b3 = sumZ

        let det =
            a11 * (a22 * a33 - a23 * a32)
            - a12 * (a21 * a33 - a23 * a31)
            + a13 * (a21 * a32 - a22 * a31)
        guard abs(det) > 1e-6 else { return 0 }

        let detA =
            b1 * (a22 * a33 - a23 * a32)
            - a12 * (b2 * a33 - a23 * b3)
            + a13 * (b2 * a32 - a22 * b3)
        let detB =
            a11 * (b2 * a33 - a23 * b3)
            - b1 * (a21 * a33 - a23 * a31)
            + a13 * (a21 * b3 - b2 * a31)
        let detC =
            a11 * (a22 * b3 - b2 * a32)
            - a12 * (a21 * b3 - b2 * a31)
            + b1 * (a21 * a32 - a22 * a31)

        let a = detA / det
        let b = detB / det
        let c = detC / det

        var err: Float = 0
        for s in samples {
            let d = s.z - (a * s.x + b * s.y + c)
            err += d * d
        }
        return sqrt(err / n)
    }

    private static func noseProminence(samples: [Sample], rect: CGRect) -> Float {
        let midX = Float(rect.midX)
        let midY = Float(rect.midY)
        let halfW = max(Float(rect.width) * 0.5, 1)
        let halfH = max(Float(rect.height) * 0.5, 1)

        var center: [Float] = []
        var cheeks: [Float] = []
        for s in samples {
            let nx = (s.x - midX) / halfW
            let ny = (s.y - midY) / halfH
            if abs(nx) < 0.28 && abs(ny) < 0.35 {
                center.append(s.z)
            } else if abs(nx) > 0.45 && abs(ny) < 0.45 {
                cheeks.append(s.z)
            }
        }
        guard center.count >= 4, cheeks.count >= 4 else { return -1 }
        let cMean = center.reduce(0, +) / Float(center.count)
        let cheekMean = cheeks.reduce(0, +) / Float(cheeks.count)
        // Closer = smaller depth. Positive ⇒ nose closer than cheeks.
        return cheekMean - cMean
    }

    /// Median depth (meters) in the tight face crop — used for depth–motion checks.
    static func medianDepth(depthData: AVDepthData, faceBox: CGRect) -> Float? {
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

        let insetBox = faceBox.insetBy(dx: faceBox.width * 0.28, dy: faceBox.height * 0.30)
        let rect = CGRect(
            x: insetBox.minX * CGFloat(width),
            y: (1 - insetBox.maxY) * CGFloat(height),
            width: insetBox.width * CGFloat(width),
            height: insetBox.height * CGFloat(height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 6, rect.height > 6 else { return nil }

        var depths: [Float] = []
        let stepX = max(1, Int(rect.width) / 14)
        let stepY = max(1, Int(rect.height) / 14)
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: stepY) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: stepX) {
                let d = row[x]
                if d.isFinite, d > 0.11, d < 1.35 {
                    depths.append(d)
                }
            }
        }
        guard depths.count >= 8 else { return nil }
        depths.sort()
        return depths[depths.count / 2]
    }
}
