//
//  HeadPoseEstimator.swift
//  ConsTrakr
//

import CoreGraphics
import Foundation
import Vision

/// Estimates approximate head yaw/pitch from Vision face landmarks (no Core ML required).
enum HeadPoseEstimator {
    /// Center band — stay inside this for "look straight".
    private static let centerYawLimit = 0.10
    private static let centerPitchLimit = 0.10
    /// Minimum angle to accept a directional pose (radians ≈ 5°).
    private static let turnYawMinimum = 0.09
    private static let turnPitchMinimum = 0.08

    static func estimate(from observation: VNFaceObservation) -> (yaw: Double, pitch: Double, roll: Double) {
        // Prefer Vision's built-in pose angles when available (iOS 15+).
        // Convention: positive yaw = face looking toward the right side of the image.
        if let yaw = observation.yaw?.doubleValue,
           let pitch = observation.pitch?.doubleValue {
            let roll = observation.roll?.doubleValue ?? 0
            return (yaw, pitch, roll)
        }

        // Fallback: derive coarse pose from landmark geometry.
        guard let landmarks = observation.landmarks,
              let nose = landmarks.noseCrest?.normalizedPoints.first
                ?? landmarks.nose?.normalizedPoints.first,
              let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints,
              !leftEye.isEmpty,
              !rightEye.isEmpty
        else {
            return (0, 0, 0)
        }

        let leftCenter = averagePoint(leftEye)
        let rightCenter = averagePoint(rightEye)
        let eyeMidX = (leftCenter.x + rightCenter.x) / 2
        let eyeMidY = (leftCenter.y + rightCenter.y) / 2

        // Nose shifting toward the right of the face box ≈ looking right in image space.
        let yaw = Double(nose.x - eyeMidX) * 3.0
        let pitch = Double(nose.y - eyeMidY) * 3.0
        let roll = atan2(Double(rightCenter.y - leftCenter.y), Double(rightCenter.x - leftCenter.x))
        return (yaw, pitch, roll)
    }

    /// Maps Vision image-space angles to enrollment poses from the **subject's** perspective
    /// on a mirrored front camera (selfie): turning YOUR left → face moves toward the
    /// right side of the mirrored image → positive yaw.
    static func classify(yaw: Double, pitch: Double) -> FacePose {
        if abs(yaw) < centerYawLimit && abs(pitch) < centerPitchLimit {
            return .center
        }
        if abs(yaw) >= abs(pitch) {
            return yaw > 0 ? .left : .right
        }
        return pitch > 0 ? .up : .down
    }

    /// Pose-specific matching — more forgiving than requiring a single exclusive class.
    static func matches(_ pose: FacePose, yaw: Double, pitch: Double) -> Bool {
        switch pose {
        case .center:
            return abs(yaw) < centerYawLimit && abs(pitch) < centerPitchLimit
        case .left:
            // Subject's left on mirrored selfie → positive yaw in image space.
            return yaw >= turnYawMinimum
        case .right:
            return yaw <= -turnYawMinimum
        case .up:
            return pitch >= turnPitchMinimum
        case .down:
            return pitch <= -turnPitchMinimum
        }
    }

    private static func averagePoint(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}
