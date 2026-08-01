//
//  DepthMotionValidator.swift
//  ConsTrakr
//
//  Detects screen/video replay: the 2D face box can grow (zoomed video) while TrueDepth
//  still measures the same flat glass distance. A live person moving closer changes both.
//

import AVFoundation
import CoreGraphics
import Foundation

final class DepthMotionValidator {
    private var baselineArea: CGFloat?
    private var baselineMedianDepth: Float?
    private var closestArea: CGFloat = 0
    private var closestMedianDepth: Float?
    private var confirmDepthSamples: [Float] = []
    private let maxConfirmSamples = 14

    func reset() {
        baselineArea = nil
        baselineMedianDepth = nil
        closestArea = 0
        closestMedianDepth = nil
        confirmDepthSamples.removeAll()
    }

    func resetConfirmSamples() {
        confirmDepthSamples.removeAll()
    }

    func observeMoveCloser(faceArea: CGFloat, depthData: AVDepthData, faceBox: CGRect) {
        guard faceArea > 0.001,
              let median = DepthFlatnessDetector.medianDepth(depthData: depthData, faceBox: faceBox)
        else { return }

        if baselineArea == nil {
            baselineArea = faceArea
            baselineMedianDepth = median
        }
        if faceArea >= closestArea {
            closestArea = faceArea
            closestMedianDepth = median
        }
    }

    /// After “move closer”, the face box must grow AND measured depth must drop (real 3D motion).
    func passedMoveCloserDepthCheck() -> Bool {
        guard let baseArea = baselineArea,
              let baseDepth = baselineMedianDepth,
              let closeDepth = closestMedianDepth,
              closestArea > 0
        else { return false }

        let areaRatio = closestArea / max(baseArea, 0.0001)
        guard areaRatio >= 1.30 else { return false }

        // Screen replay: face zooms in video but depth to the display plane barely changes.
        let depthDrop = (baseDepth - closeDepth) / max(baseDepth, 0.01)
        return depthDrop >= 0.05
    }

    func observeDepthConfirm(depthData: AVDepthData, faceBox: CGRect) {
        guard let median = DepthFlatnessDetector.medianDepth(depthData: depthData, faceBox: faceBox) else {
            return
        }
        confirmDepthSamples.append(median)
        if confirmDepthSamples.count > maxConfirmSamples {
            confirmDepthSamples.removeFirst(confirmDepthSamples.count - maxConfirmSamples)
        }
    }

    /// Scrubbing/rewinding video jumps scene depth; a still live face stays stable.
    func depthConfirmIsStable() -> Bool {
        guard confirmDepthSamples.count >= 6 else { return true }
        let mean = confirmDepthSamples.reduce(0, +) / Float(confirmDepthSamples.count)
        var variance: Float = 0
        for sample in confirmDepthSamples {
            let delta = sample - mean
            variance += delta * delta
        }
        variance /= Float(confirmDepthSamples.count)
        let stdDev = sqrt(variance)
        return stdDev < 0.022
    }
}
