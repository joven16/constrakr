//
//  MaskMaterialDetector.swift
//  ConsTrakr
//
// Heuristics against 3D masks / silicone faces:
// - RGB skin microtexture is usually richer than smooth mask material
// - TrueDepth center (nose) should be clearly closer than cheek edges
//

import AVFoundation
import CoreVideo
import Foundation

enum MaskMaterialDetector {
    struct Verdict {
        let isSuspicious: Bool
        let reason: String?
    }

    /// Combine depth shape + RGB texture. Call when a face is present.
    static func evaluate(
        pixelBuffer: CVPixelBuffer,
        depthData: AVDepthData?,
        faceBox: CGRect
    ) -> Verdict {
        if let depthData {
            let shape = depthShapeVerdict(depthData: depthData, faceBox: faceBox)
            if shape.isSuspicious { return shape }
        }
        return textureVerdict(pixelBuffer: pixelBuffer, faceBox: faceBox)
    }

    /// Nose / center of face should be closer (smaller meters) than side cheeks.
    private static func depthShapeVerdict(depthData: AVDepthData, faceBox: CGRect) -> Verdict {
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
            return Verdict(isSuspicious: false, reason: nil)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)

        let rect = CGRect(
            x: faceBox.minX * CGFloat(width),
            y: (1 - faceBox.maxY) * CGFloat(height),
            width: faceBox.width * CGFloat(width),
            height: faceBox.height * CGFloat(height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 12, rect.height > 12 else {
            return Verdict(isSuspicious: false, reason: nil)
        }

        func sampleMean(in region: CGRect) -> Float? {
            let r = region.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard r.width > 2, r.height > 2 else { return nil }
            var sum: Float = 0
            var count: Float = 0
            let step = max(1, Int(min(r.width, r.height) / 8))
            for y in stride(from: Int(r.minY), to: Int(r.maxY), by: step) {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in stride(from: Int(r.minX), to: Int(r.maxX), by: step) {
                    let d = row[x]
                    if d.isFinite, d > 0.15, d < 1.8 {
                        sum += d
                        count += 1
                    }
                }
            }
            guard count >= 6 else { return nil }
            return sum / count
        }

        let center = CGRect(
            x: rect.midX - rect.width * 0.12,
            y: rect.midY - rect.height * 0.08,
            width: rect.width * 0.24,
            height: rect.height * 0.22
        )
        let leftCheek = CGRect(
            x: rect.minX + rect.width * 0.05,
            y: rect.midY - rect.height * 0.08,
            width: rect.width * 0.22,
            height: rect.height * 0.22
        )
        let rightCheek = CGRect(
            x: rect.maxX - rect.width * 0.27,
            y: rect.midY - rect.height * 0.08,
            width: rect.width * 0.22,
            height: rect.height * 0.22
        )

        guard let c = sampleMean(in: center),
              let l = sampleMean(in: leftCheek),
              let r = sampleMean(in: rightCheek)
        else {
            return Verdict(isSuspicious: false, reason: nil)
        }

        let cheekMean = (l + r) / 2
        // Real nose is closer → smaller depth. Masks / shells often lack this relief.
        let noseProminence = cheekMean - c
        if noseProminence < 0.0025 {
            return Verdict(
                isSuspicious: true,
                reason: "Face depth shape looks unnatural (possible mask)."
            )
        }
        return Verdict(isSuspicious: false, reason: nil)
    }

    /// Silicone / printed masks often lack fine skin texture (pores, stubble micro-edges).
    private static func textureVerdict(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> Verdict {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return Verdict(isSuspicious: false, reason: nil)
        }

        let inset = faceBox.insetBy(dx: faceBox.width * 0.25, dy: faceBox.height * 0.28)
        let rect = CGRect(
            x: inset.minX * CGFloat(width),
            y: (1 - inset.maxY) * CGFloat(height),
            width: inset.width * CGFloat(width),
            height: inset.height * CGFloat(height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 20, rect.height > 20 else {
            return Verdict(isSuspicious: false, reason: nil)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Verdict(isSuspicious: false, reason: nil)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        func luma(_ x: Int, _ y: Int) -> Float {
            let px = min(max(x, 0), width - 1)
            let py = min(max(y, 0), height - 1)
            let p = base.advanced(by: py * bytesPerRow + px * 4).assumingMemoryBound(to: UInt8.self)
            return (0.299 * Float(p[2]) + 0.587 * Float(p[1]) + 0.114 * Float(p[0])) / 255
        }

        var edgeSum: Float = 0
        var count: Float = 0
        let step = max(1, Int(min(rect.width, rect.height) / 28))
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY) - step, by: step) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX) - step, by: step) {
                let l = luma(x, y)
                let dx = abs(luma(x + step, y) - l)
                let dy = abs(luma(x, y + step) - l)
                edgeSum += dx + dy
                count += 1
            }
        }
        guard count > 30 else { return Verdict(isSuspicious: false, reason: nil) }
        let microTexture = edgeSum / count

        // Very smooth mid-face → likely mask / printed surface under even lighting.
        if microTexture < 0.011 {
            return Verdict(
                isSuspicious: true,
                reason: "Skin texture looks unnatural (possible mask)."
            )
        }
        return Verdict(isSuspicious: false, reason: nil)
    }
}
