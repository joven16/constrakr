//
//  DetectedFace.swift
//  ConsTrac
//

import CoreGraphics
import Foundation

struct DetectedFace {
    let boundingBox: CGRect
    let confidence: Float
    let yaw: Double
    let pitch: Double
    let roll: Double

    var estimatedPose: FacePose {
        HeadPoseEstimator.classify(yaw: yaw, pitch: pitch)
    }
}
