//
//  FacePose.swift
//  ConsTrakr
//

import Foundation

/// Poses captured during employee face enrollment.
enum FacePose: String, Codable, CaseIterable, Identifiable {
    case center
    case left
    case right
    case up
    case down

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .center: return "Look Straight"
        case .left: return "Look Left"
        case .right: return "Look Right"
        case .up: return "Look Up"
        case .down: return "Look Down"
        }
    }

    var instruction: String {
        switch self {
        case .center: return "Face the camera directly"
        case .left: return "Turn toward your left shoulder"
        case .right: return "Turn toward your right shoulder"
        case .up: return "Tilt your chin slightly upward"
        case .down: return "Tilt your chin slightly downward"
        }
    }

    var systemImage: String {
        switch self {
        case .center: return "face.smiling"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        }
    }

    var next: FacePose? {
        next(in: Self.enrollmentOrder)
    }

    static let enrollmentOrder: [FacePose] = [.center, .left, .right, .up, .down]

    func next(in poses: [FacePose]) -> FacePose? {
        guard let index = poses.firstIndex(of: self), index + 1 < poses.count else { return nil }
        return poses[index + 1]
    }
}
