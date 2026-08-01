//
//  PresentationSpoofDetector.swift
//  ConsTrakr
//
// Heuristics to reject faces replayed on a phone/laptop screen (presentation attacks).
// Used as a fallback when TrueDepth is unavailable (rear camera / older devices).
//

import CoreVideo
import Foundation
import QuartzCore

enum PresentationSpoofDetector {
    struct Sample {
        let meanLuma: Float
        let lumaVariance: Float
        let highFreqEnergy: Float
        let borderContrast: Float
        let timestamp: CFTimeInterval
    }

    final class Tracker {
        private var samples: [Sample] = []
        private let maxSamples = 20
        private(set) var spoofScore: Float = 0
        private(set) var rejectReason: String?

        func reset() {
            samples.removeAll()
            spoofScore = 0
            rejectReason = nil
        }

        /// Returns true when the face region looks like a digital display replay.
        @discardableResult
        func observe(
            pixelBuffer: CVPixelBuffer,
            faceBox: CGRect,
            rejectThreshold: Float = 0.68
        ) -> Bool {
            guard let sample = Self.sample(pixelBuffer: pixelBuffer, faceBox: faceBox) else {
                return false
            }
            samples.append(sample)
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
            guard samples.count >= 12 else { return false }

            let flicker = temporalFlickerScore()
            let flat = flatScreenScore()
            let bezel = bezelScore()
            // Bezel is a weak signal indoors (dark walls / bright windows) — keep it low weight.
            spoofScore = min(1, flicker * 0.45 + flat * 0.40 + bezel * 0.15)

            if spoofScore >= rejectThreshold {
                rejectReason = "Screen or video replay detected. Use a live person."
                return true
            }
            rejectReason = nil
            return false
        }

        private func temporalFlickerScore() -> Float {
            var diffs: [Float] = []
            for i in 1..<samples.count {
                diffs.append(abs(samples[i].meanLuma - samples[i - 1].meanLuma))
            }
            guard !diffs.isEmpty else { return 0 }
            let meanDiff = diffs.reduce(0, +) / Float(diffs.count)
            var varDiff: Float = 0
            for d in diffs {
                let x = d - meanDiff
                varDiff += x * x
            }
            varDiff /= Float(diffs.count)
            let score = min(1, meanDiff / 0.045 + varDiff / 0.0018)
            return max(0, score - 0.45)
        }

        private func flatScreenScore() -> Float {
            let latest = samples.suffix(6)
            let avgHF = latest.map(\.highFreqEnergy).reduce(0, +) / Float(latest.count)
            let avgVar = latest.map(\.lumaVariance).reduce(0, +) / Float(latest.count)
            let hfScore = min(1, avgHF / 0.11)
            let varScore = avgVar < 0.018 ? 0.7 : max(0, 1 - (avgVar - 0.018) / 0.09)
            return min(1, hfScore * 0.5 + varScore * 0.5)
        }

        private func bezelScore() -> Float {
            let latest = samples.suffix(8)
            let avg = latest.map(\.borderContrast).reduce(0, +) / Float(latest.count)
            // Only strong rectangular luminance jumps count.
            return min(1, max(0, (avg - 0.18) / 0.22))
        }

        private static func sample(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> Sample? {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let rect = CGRect(
                x: faceBox.minX * CGFloat(width),
                y: (1 - faceBox.maxY) * CGFloat(height),
                width: faceBox.width * CGFloat(width),
                height: faceBox.height * CGFloat(height)
            ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))

            guard rect.width > 16, rect.height > 16 else { return nil }
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            var sum: Float = 0
            var sumSq: Float = 0
            var edge: Float = 0
            var count: Float = 0
            let step = max(1, Int(min(rect.width, rect.height) / 32))

            let minX = Int(rect.minX)
            let minY = Int(rect.minY)
            let maxX = Int(rect.maxX)
            let maxY = Int(rect.maxY)

            func lumaAt(_ x: Int, _ y: Int) -> Float {
                let px = min(max(x, 0), width - 1)
                let py = min(max(y, 0), height - 1)
                let pixel = base.advanced(by: py * bytesPerRow + px * 4).assumingMemoryBound(to: UInt8.self)
                let b = Float(pixel[0])
                let g = Float(pixel[1])
                let r = Float(pixel[2])
                return (0.299 * r + 0.587 * g + 0.114 * b) / 255
            }

            for y in stride(from: minY, to: maxY - step, by: step) {
                for x in stride(from: minX, to: maxX - step, by: step) {
                    let l = lumaAt(x, y)
                    sum += l
                    sumSq += l * l
                    let dx = abs(lumaAt(x + step, y) - l)
                    let dy = abs(lumaAt(x, y + step) - l)
                    edge += dx + dy
                    count += 1
                }
            }
            guard count > 8 else { return nil }
            let mean = sum / count
            let variance = max(0, sumSq / count - mean * mean)
            let highFreq = edge / count

            // Ring just outside the face — screens often show a hard luminance jump (bezel / LCD edge).
            let padX = max(8, Int(rect.width * 0.18))
            let padY = max(8, Int(rect.height * 0.18))
            var borderSum: Float = 0
            var borderCount: Float = 0
            let samplesAround: [(Int, Int)] = [
                (minX - padX, (minY + maxY) / 2),
                (maxX + padX, (minY + maxY) / 2),
                ((minX + maxX) / 2, minY - padY),
                ((minX + maxX) / 2, maxY + padY),
                (minX - padX, minY - padY),
                (maxX + padX, minY - padY),
                (minX - padX, maxY + padY),
                (maxX + padX, maxY + padY)
            ]
            for (x, y) in samplesAround {
                borderSum += abs(lumaAt(x, y) - mean)
                borderCount += 1
            }
            let borderContrast = borderCount > 0 ? borderSum / borderCount : 0

            return Sample(
                meanLuma: mean,
                lumaVariance: variance,
                highFreqEnergy: highFreq,
                borderContrast: borderContrast,
                timestamp: CACurrentMediaTime()
            )
        }
    }
}
