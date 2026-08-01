//
//  DetectedFace.swift
//  ConsTrakr
//

import CoreGraphics
import Foundation

struct DetectedFace {
    let boundingBox: CGRect
    let confidence: Float
    let yaw: Double
    let pitch: Double
    let roll: Double
    /// Eye aspect ratios (lower ≈ closed). Nil when landmarks are missing.
    let leftEyeEAR: Float?
    let rightEyeEAR: Float?

    var estimatedPose: FacePose {
        HeadPoseEstimator.classify(yaw: yaw, pitch: pitch)
    }
}
