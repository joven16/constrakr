//
//  ConsTrakrTests.swift
//  ConsTrakrTests
//

import Foundation
import Testing
@testable import ConsTrakr

@Suite(.serialized)
struct ConsTrakrTests {

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

    @Test func faceScanSettingsBuildScannerSteps() {
        defer { FaceScanSettings.applyLevel(.full) }

        FaceScanSettings.applyLevel(.basic)
        #expect(FaceScanSettings.scannerLivenessSteps() == [.blink, .moveCloser])

        FaceScanSettings.applyLevel(.standard)
        #expect(FaceScanSettings.scannerLivenessSteps() == [.blink, .turnLeft, .turnRight, .moveCloser])

        FaceScanSettings.applyLevel(.full)
        #expect(
            FaceScanSettings.scannerLivenessSteps()
                == [.blink, .turnLeft, .turnRight, .nodUp, .nodDown, .moveCloser]
        )

        FaceScanSettings.setStepEnabled(.lookDown, false)
        #expect(FaceScanSettings.scannerLivenessSteps().contains(.nodDown) == false)
        #expect(FaceScanSettings.isCustomConfiguration)

        FaceScanSettings.applyLevel(.standard)
        FaceScanSettings.setStepEnabled(.closeUp, false)
        FaceScanSettings.setStepEnabled(.lookLeft, false)
        FaceScanSettings.setStepEnabled(.lookRight, false)
        FaceScanSettings.setStepEnabled(.lookUp, false)
        FaceScanSettings.setStepEnabled(.lookDown, false)
        #expect(FaceScanSettings.scannerLivenessSteps() == [.blink])
        #expect(FaceScanSettings.isBlinkOnlyConfiguration)
        #expect(FaceScanSettings.scannerPresetLabel() == "Blink only")
    }

    @Test func faceScanReadySummaryUsesSettings() {
        defer { FaceScanSettings.applyLevel(.full) }

        FaceScanSettings.applyLevel(.standard)
        #expect(FaceScanSettings.scannerReadySummary() == "Standard · Blink · Look left · Look right · Close-up · 3D")
    }

    @Test func faceScanLevelPresets() {
        defer { FaceScanSettings.applyLevel(.full) }

        FaceScanSettings.applyLevel(.basic)
        #expect(FaceScanSettings.matchingLevel() == .basic)

        FaceScanSettings.applyLevel(.standard)
        #expect(FaceScanSettings.matchingLevel() == .standard)

        FaceScanSettings.applyLevel(.full)
        #expect(FaceScanSettings.matchingLevel() == .full)
    }

    @Test func headPoseClassifierCenter() {
        #expect(HeadPoseEstimator.classify(yaw: 0, pitch: 0) == .center)
        // Mirrored selfie: positive yaw = subject's left
        #expect(HeadPoseEstimator.classify(yaw: 0.5, pitch: 0) == .left)
        #expect(HeadPoseEstimator.classify(yaw: -0.5, pitch: 0) == .right)
        #expect(HeadPoseEstimator.matches(.left, yaw: 0.16, pitch: 0.05))
        #expect(HeadPoseEstimator.matches(.right, yaw: -0.16, pitch: 0.05))
        #expect(!HeadPoseEstimator.matches(.left, yaw: -0.2, pitch: 0))
        // Looking straight must not satisfy Look Up.
        #expect(!HeadPoseEstimator.matches(.up, yaw: 0, pitch: 0.05))
        #expect(!HeadPoseEstimator.matches(.up, yaw: 0, pitch: 0.12))
        #expect(HeadPoseEstimator.matches(.up, yaw: 0.02, pitch: 0.22))
        #expect(HeadPoseEstimator.matches(.down, yaw: 0.02, pitch: -0.22))
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
