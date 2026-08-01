//
//  FaceImagePreprocessor.swift
//  ConsTrakr
//
 // FIX: Instance-normalize the face crop (mean/std) so lighting does not dominate,
// then build texture + spatial features. Shared by enrollment and scanning.
 // INTEGRATION: Pass prepared.normalizedRGBPixels into Core ML when available.
//

import CoreGraphics
import CoreVideo
import Foundation
import os

enum FaceImagePreprocessor {
    static let modelInputSize = 48
    static let embeddingDimension = 160
    static let minFaceRelativeSize: CGFloat = 0.22

    private static let logger = Logger(subsystem: "com.constrakr", category: "FaceEmbedding")

    struct PreparedFace {
        /// Instance-normalized RGB (approx zero-mean / unit variance per channel).
        let normalizedRGBPixels: [Float]
        let cropWidth: Int
        let cropHeight: Int
        let faceAreaRatio: CGFloat
        let contrast: Float
    }

    enum PreprocessError: LocalizedError {
        case lockFailed
        case invalidCrop
        case faceTooSmall
        case lowContrast
        case unsupportedFormat
        case copyFailed

        var errorDescription: String? {
            switch self {
            case .lockFailed: return "Could not read camera frame."
            case .invalidCrop: return "Face crop is invalid."
            case .faceTooSmall: return "Move closer — face is too small or poorly aligned."
            case .lowContrast: return "Face image is too blurry or low contrast."
            case .unsupportedFormat: return "Unsupported camera pixel format."
            case .copyFailed: return "Could not copy camera frame."
            }
        }
    }

    /// Deep-copy the camera frame so recognition never reads a recycled buffer.
    static func copyPixelBuffer(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)
        var copy: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &copy
        )
        guard status == kCVReturnSuccess, let copy else { throw PreprocessError.copyFailed }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        let srcBase = CVPixelBufferGetBaseAddress(source)
        let dstBase = CVPixelBufferGetBaseAddress(copy)
        guard let srcBase, let dstBase else { throw PreprocessError.copyFailed }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(copy)
        let rowCount = CVPixelBufferGetHeight(source)
        for row in 0..<rowCount {
            memcpy(
                dstBase.advanced(by: row * dstBytesPerRow),
                srcBase.advanced(by: row * srcBytesPerRow),
                min(srcBytesPerRow, dstBytesPerRow)
            )
        }
        return copy
    }

    /// Square face crop resized for AdaFace (112×112 BGRA). Used by Core ML path.
    static func makeSquareFacePixelBuffer(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect,
        outputSize: Int
    ) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let shortSide = CGFloat(min(width, height))
        var rect = pixelRect(fromNormalizedVisionBox: boundingBox, width: width, height: height)

        // Expand to square centered on the face box.
        let side = max(rect.width, rect.height)
        let cx = rect.midX
        let cy = rect.midY
        rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard min(rect.width, rect.height) >= shortSide * minFaceRelativeSize * 0.85 else {
            throw PreprocessError.faceTooSmall
        }

        let rgb = try extractResizedRGB(pixelBuffer: pixelBuffer, crop: rect, size: outputSize)
        // Quick contrast check on raw (pre-instance-norm) RGB
        let contrast = lumaStdDev(rgb)
        guard contrast >= 0.04 else { throw PreprocessError.lowContrast }

        return try rgbFloatsToBGRAPixelBuffer(rgb, size: outputSize)
    }

    private static func rgbFloatsToBGRAPixelBuffer(_ rgb: [Float], size: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw PreprocessError.copyFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw PreprocessError.copyFailed }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        for y in 0..<size {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<size {
                let idx = (y * size + x) * 3
                let r = UInt8(max(0, min(255, Int(rgb[idx] * 255))))
                let g = UInt8(max(0, min(255, Int(rgb[idx + 1] * 255))))
                let b = UInt8(max(0, min(255, Int(rgb[idx + 2] * 255))))
                let o = x * 4
                row[o] = b
                row[o + 1] = g
                row[o + 2] = r
                row[o + 3] = 255
            }
        }
        return buffer
    }

    static func prepare(
        pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) throws -> PreparedFace {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let shortSide = CGFloat(min(width, height))

        let pixelRect = pixelRect(fromNormalizedVisionBox: boundingBox, width: width, height: height)
        let faceSize = min(pixelRect.width, pixelRect.height)
        let areaRatio = (pixelRect.width * pixelRect.height) / CGFloat(max(width * height, 1))

        guard faceSize >= shortSide * minFaceRelativeSize else {
            throw PreprocessError.faceTooSmall
        }

        var rgb = try extractResizedRGB(pixelBuffer: pixelBuffer, crop: pixelRect, size: modelInputSize)
        let contrast = lumaStdDev(rgb)
        guard contrast >= 0.05 else {
            throw PreprocessError.lowContrast
        }

        // Instance-normalize so global brightness/tint does not make all faces look alike.
        instanceNormalize(&rgb)

        return PreparedFace(
            normalizedRGBPixels: rgb,
            cropWidth: Int(pixelRect.width),
            cropHeight: Int(pixelRect.height),
            faceAreaRatio: areaRatio,
            contrast: contrast
        )
    }

    /// Discriminative embedding from the CURRENT prepared crop only.
    static func makeContentEmbedding(from prepared: PreparedFace) -> [Float] {
        let size = modelInputSize
        let pixels = prepared.normalizedRGBPixels
        var features = [Float]()
        features.reserveCapacity(embeddingDimension)

        // 1) Spatial grid of centered RGB (5×5×3 = 75)
        let cell = 5
        let step = size / cell
        for cy in 0..<cell {
            for cx in 0..<cell {
                var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0, count: Float = 0
                let y0 = cy * step
                let x0 = cx * step
                let y1 = (cy == cell - 1) ? size : (cy + 1) * step
                let x1 = (cx == cell - 1) ? size : (cx + 1) * step
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let idx = (y * size + x) * 3
                        rSum += pixels[idx]
                        gSum += pixels[idx + 1]
                        bSum += pixels[idx + 2]
                        count += 1
                    }
                }
                let inv = count > 0 ? 1 / count : 0
                features.append(rSum * inv)
                features.append(gSum * inv)
                features.append(bSum * inv)
            }
        }

        // 2) Local Binary Pattern histogram (texture identity) — 36 bins
        features.append(contentsOf: lbpHistogram(pixels: pixels, size: size, bins: 36))

        // 3) Horizontal + vertical luma projections (structure) — 24 + 24
        let projBins = 24
        var hProj = [Float](repeating: 0, count: projBins)
        var vProj = [Float](repeating: 0, count: projBins)
        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 3
                let luma = 0.299 * pixels[idx] + 0.587 * pixels[idx + 1] + 0.114 * pixels[idx + 2]
                hProj[x * projBins / size] += luma
                vProj[y * projBins / size] += luma
            }
        }
        let hMax = max(hProj.max() ?? 1, 1e-5)
        let vMax = max(vProj.max() ?? 1, 1e-5)
        features.append(contentsOf: hProj.map { $0 / hMax })
        features.append(contentsOf: vProj.map { $0 / vMax })

        // 4) Neighbor patch deltas (relative structure) — fills remaining dims
        while features.count < embeddingDimension {
            let i = features.count
            let a = features[i % 75]
            let b = features[(i + 7) % 75]
            features.append(a - b)
        }
        if features.count > embeddingDimension {
            features = Array(features.prefix(embeddingDimension))
        }

        return l2Normalize(features)
    }

    static func l2Normalize(_ values: [Float]) -> [Float] {
        var sumSquares: Float = 0
        for v in values { sumSquares += v * v }
        let norm = sqrt(sumSquares)
        guard norm > 1e-6 else { return values }
        return values.map { $0 / norm }
    }

    static func l2Norm(_ values: [Float]) -> Float {
        sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
    }

    /// Cosine distance equivalent gate: for unit vectors, dist^2 = 2 - 2*dot.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let na = l2Normalize(a)
        let nb = l2Normalize(b)
        guard na.count == nb.count, !na.isEmpty else { return 0 }
        var dot: Float = 0
        for i in na.indices { dot += na[i] * nb[i] }
        return min(max(dot, -1), 1)
    }

    // MARK: - Private

    private static func instanceNormalize(_ rgb: inout [Float]) {
        let n = rgb.count / 3
        guard n > 0 else { return }
        var mean: (Float, Float, Float) = (0, 0, 0)
        for i in 0..<n {
            let idx = i * 3
            mean.0 += rgb[idx]
            mean.1 += rgb[idx + 1]
            mean.2 += rgb[idx + 2]
        }
        let invN = 1 / Float(n)
        mean.0 *= invN; mean.1 *= invN; mean.2 *= invN

        var varSum: (Float, Float, Float) = (0, 0, 0)
        for i in 0..<n {
            let idx = i * 3
            let dr = rgb[idx] - mean.0
            let dg = rgb[idx + 1] - mean.1
            let db = rgb[idx + 2] - mean.2
            varSum.0 += dr * dr
            varSum.1 += dg * dg
            varSum.2 += db * db
        }
        let stdR = max(sqrt(varSum.0 * invN), 1e-3)
        let stdG = max(sqrt(varSum.1 * invN), 1e-3)
        let stdB = max(sqrt(varSum.2 * invN), 1e-3)

        for i in 0..<n {
            let idx = i * 3
            rgb[idx] = (rgb[idx] - mean.0) / stdR
            rgb[idx + 1] = (rgb[idx + 1] - mean.1) / stdG
            rgb[idx + 2] = (rgb[idx + 2] - mean.2) / stdB
        }
    }

    private static func lbpHistogram(pixels: [Float], size: Int, bins: Int) -> [Float] {
        var hist = [Float](repeating: 0, count: bins)
        func luma(_ x: Int, _ y: Int) -> Float {
            let idx = (y * size + x) * 3
            return 0.299 * pixels[idx] + 0.587 * pixels[idx + 1] + 0.114 * pixels[idx + 2]
        }
        let offsets = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let center = luma(x, y)
                var code = 0
                for (i, off) in offsets.enumerated() {
                    if luma(x + off.0, y + off.1) >= center {
                        code |= (1 << i)
                    }
                }
                hist[code % bins] += 1
            }
        }
        let total = max(hist.reduce(0, +), 1)
        return hist.map { $0 / total }
    }

    private static func pixelRect(fromNormalizedVisionBox box: CGRect, width: Int, height: Int) -> CGRect {
        let pad: CGFloat = 0.06
        var x = box.minX - pad * box.width
        var yBottom = box.minY - pad * box.height
        var w = box.width * (1 + 2 * pad)
        var h = box.height * (1 + 2 * pad)
        x = max(0, min(1, x))
        yBottom = max(0, min(1, yBottom))
        w = min(1 - x, w)
        h = min(1 - yBottom, h)

        let minX = Int(x * CGFloat(width))
        let maxX = Int((x + w) * CGFloat(width))
        let top = Int((1 - (yBottom + h)) * CGFloat(height))
        let bottom = Int((1 - yBottom) * CGFloat(height))
        let rect = CGRect(
            x: minX,
            y: min(top, bottom),
            width: max(1, maxX - minX),
            height: max(1, abs(bottom - top))
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func extractResizedRGB(
        pixelBuffer: CVPixelBuffer,
        crop: CGRect,
        size: Int
    ) throws -> [Float] {
        let lock = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lock == kCVReturnSuccess else { throw PreprocessError.lockFailed }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PreprocessError.lockFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            throw PreprocessError.unsupportedFormat
        }

        let cropX = Int(crop.minX)
        let cropY = Int(crop.minY)
        let cropW = max(1, Int(crop.width))
        let cropH = max(1, Int(crop.height))
        guard cropW > 1, cropH > 1 else { throw PreprocessError.invalidCrop }

        var rgb = [Float](repeating: 0, count: size * size * 3)
        for oy in 0..<size {
            for ox in 0..<size {
                let srcX = cropX + ox * cropW / size
                let srcY = cropY + oy * cropH / size
                let pixel = base
                    .advanced(by: srcY * bytesPerRow + srcX * 4)
                    .assumingMemoryBound(to: UInt8.self)
                let b = Float(pixel[0]) / 255.0
                let g = Float(pixel[1]) / 255.0
                let r = Float(pixel[2]) / 255.0
                let idx = (oy * size + ox) * 3
                rgb[idx] = r
                rgb[idx + 1] = g
                rgb[idx + 2] = b
            }
        }
        return rgb
    }

    private static func lumaStdDev(_ rgb: [Float]) -> Float {
        let n = rgb.count / 3
        guard n > 0 else { return 0 }
        var mean: Float = 0
        for i in 0..<n {
            let idx = i * 3
            mean += 0.299 * rgb[idx] + 0.587 * rgb[idx + 1] + 0.114 * rgb[idx + 2]
        }
        mean /= Float(n)
        var varSum: Float = 0
        for i in 0..<n {
            let idx = i * 3
            let luma = 0.299 * rgb[idx] + 0.587 * rgb[idx + 1] + 0.114 * rgb[idx + 2]
            let d = luma - mean
            varSum += d * d
        }
        return sqrt(varSum / Float(n))
    }
}
