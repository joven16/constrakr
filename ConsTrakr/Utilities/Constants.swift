//
//  Constants.swift
//  ConsTrakr
//

import Foundation

enum AppConstants {
    static let appName = "ConsTrakr"
    static let apiBaseURL = "https://api.constrakr.example.com/v1"

    // MARK: Matching thresholds
    // AdaFace cosine: same person often ~0.4–0.8; strangers usually << 0.35.
    static let adaFaceMatchThreshold: Float = 0.42
    static let adaFaceSoloGalleryThreshold: Float = 0.45
    // Handcrafted fallback (much weaker — keep stricter / expect more unknowns).
    static let faceMatchThreshold: Float = 0.88
    static let soloGalleryMatchThreshold: Float = 0.90

    static let multiPoseMeanSlack: Float = 0.12
    static let faceMatchMargin: Float = 0.04
    static let minFaceConfidence: Float = 0.55
    static let poseHoldDuration: TimeInterval = 0.6
    static let scannerCooldown: TimeInterval = 3.0
    static let scannerWarmupFrames: Int = 8
    static let scannerConsensusFrames: Int = 2
    static let syncIntervalSeconds: TimeInterval = 30
    static let registrationResetDelay: TimeInterval = 2.5

    enum UserDefaultsKeys {
        static let apiBaseURL = "settings.apiBaseURL"
        static let autoSyncEnabled = "settings.autoSyncEnabled"
        static let matchThreshold = "settings.matchThreshold"
        static let hasSeededMockData = "app.hasSeededMockData"
        static let uploadRawFramesEnabled = "settings.uploadRawFramesEnabled"
        static let thresholdMigratedForAdaFace = "settings.thresholdMigratedForAdaFace"
    }

    enum Notifications {
        static let attendanceHistoryDidClear = Notification.Name("constrakr.attendanceHistoryDidClear")
    }
}
