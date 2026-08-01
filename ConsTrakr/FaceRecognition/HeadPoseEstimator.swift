//
//  HeadPoseEstimator.swift
//  ConsTrakr
//

import CoreGraphics
import Foundation
import Vision

/// Estimates approximate head yaw/pitch from Vision face landmarks (no Core ML required).
/// Pitch convention used everywhere in ConsTrakr:
///   positive = looking up (chin up), negative = looking down (chin down).
enum HeadPoseEstimator {
    /// Center band — stay inside this for "look straight".
    private static let centerYawLimit = 0.10
    private static let centerPitchLimit = 0.10
    /// Yaw turn must be clearly intentional.
    private static let turnYawMinimum = 0.14
    /// Look Up — keep fairly strict so resting face does not count.
    private static let lookUpPitchMinimum = 0.16
    /// Look Down — slightly easier; chin-down is harder on a selfie angle.
    private static let lookDownPitchMinimum = 0.12
    /// Pitch must dominate yaw so a slight chin move isn't enough while mostly turned.
    private static let pitchDominanceMargin = 0.02

    static func estimate(from observation: VNFaceObservation) -> (yaw: Double, pitch: Double, roll: Double) {
        // Prefer Vision's built-in pose angles when available (iOS 15+).
        // Convention: positive yaw = face looking toward the right side of the image.
        // Vision pitch: positive = nodding DOWN. We invert to positive = looking UP.
        if let yaw = observation.yaw?.doubleValue,
           let visionPitch = observation.pitch?.doubleValue {
            let roll = observation.roll?.doubleValue ?? 0
            return (yaw, -visionPitch, roll)
        }

        // Fallback: derive coarse pose from landmark geometry (already +up / −down).
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

    /// Pose-specific matching — directional poses require a clear, intentional angle.
    static func matches(_ pose: FacePose, yaw: Double, pitch: Double) -> Bool {
        switch pose {
        case .center:
            return abs(yaw) < centerYawLimit && abs(pitch) < centerPitchLimit
        case .left:
            // Subject's left on mirrored selfie → positive yaw in image space.
            return yaw >= turnYawMinimum && abs(yaw) >= abs(pitch)
        case .right:
            return yaw <= -turnYawMinimum && abs(yaw) >= abs(pitch)
        case .up:
            return pitch >= lookUpPitchMinimum
                && abs(pitch) >= abs(yaw) + pitchDominanceMargin
        case .down:
            return pitch <= -lookDownPitchMinimum
                && abs(pitch) >= abs(yaw) + pitchDominanceMargin
        }
    }

    private static func averagePoint(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}
