//
//  ConsTracTests.swift
//  ConsTracTests
//

import Testing
@testable import ConsTrac

struct ConsTracTests {

    @Test func faceEmbeddingCosineSimilarityIdentical() {
        let a = FaceEmbedding.placeholder(for: .center, seed: 42)
        let b = FaceEmbedding.placeholder(for: .center, seed: 42)
        #expect(a.cosineSimilarity(to: b) > 0.99)
    }

    @Test func facePoseSequenceCoversEnrollment() {
        #expect(FacePose.allCases.count == 5)
        #expect(FacePose.center.next == .left)
        #expect(FacePose.down.next == nil)
    }

    @Test func headPoseClassifierCenter() {
        #expect(HeadPoseEstimator.classify(yaw: 0, pitch: 0) == .center)
        // Mirrored selfie: positive yaw = subject's left
        #expect(HeadPoseEstimator.classify(yaw: 0.5, pitch: 0) == .left)
        #expect(HeadPoseEstimator.classify(yaw: -0.5, pitch: 0) == .right)
        #expect(HeadPoseEstimator.matches(.left, yaw: 0.12, pitch: 0.05))
        #expect(HeadPoseEstimator.matches(.right, yaw: -0.12, pitch: 0.05))
        #expect(!HeadPoseEstimator.matches(.left, yaw: -0.2, pitch: 0))
    }

    @Test func matchThresholdIsConfigurable() {
        let previous = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.matchThreshold)
        let previousFlag = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.thresholdMigratedForAdaFace)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppConstants.UserDefaultsKeys.matchThreshold)
            } else {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.matchThreshold)
            }
            if let previousFlag {
                UserDefaults.standard.set(previousFlag, forKey: AppConstants.UserDefaultsKeys.thresholdMigratedForAdaFace)
            } else {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.thresholdMigratedForAdaFace)
            }
        }
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.thresholdMigratedForAdaFace)
        UserDefaults.standard.set(0.45, forKey: AppConstants.UserDefaultsKeys.matchThreshold)
        #expect(MatchThresholdSettings.current == 0.45)
    }
}
