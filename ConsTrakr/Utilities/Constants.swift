//
//  Constants.swift
//  ConsTrakr
//

import Foundation

enum AppConstants {
    static let appName = "ConsTrakr"
    /// Host root only — `/constrakr-api` is appended automatically.
    /// Host root only — `/constrakr-api` is appended automatically.
    static let apiBaseURL = "https://ims.rentelloph.com"
    static let apiPathPrefix = "/constrakr-api"

    // MARK: Matching thresholds
    // AdaFace cosine: same person often ~0.42–0.80; strangers usually << 0.35.
    static let adaFaceMatchThreshold: Float = 0.45
    static let adaFaceSoloGalleryThreshold: Float = 0.48
    // Handcrafted fallback (much weaker — keep stricter / expect more unknowns).
    static let faceMatchThreshold: Float = 0.88
    static let soloGalleryMatchThreshold: Float = 0.90

    /// Mean of top pose scores must stay within this of the threshold (not all 5 poses).
    static let multiPoseMeanSlack: Float = 0.16
    static let faceMatchMargin: Float = 0.06
    static let minFaceConfidence: Float = 0.55
    static let poseHoldDuration: TimeInterval = 0.6
    static let scannerCooldown: TimeInterval = 3.0
    static let unknownPersonAutoCancelDelay: TimeInterval = 3.0
    /// Brief success / already-recorded message before returning to Ready.
    static let scannerResultDismissDelay: TimeInterval = 2.0
    static let scannerWarmupFrames: Int = 3
    static let scannerConsensusFrames: Int = 2
    static let registrationResetDelay: TimeInterval = 2.5
    /// Maximum allowed drift between device clock and IMS server time when online.
    static let maxClockDriftSeconds: TimeInterval = 300
    /// Detect manual date/time changes between punches.
    static let maxClockJumpToleranceSeconds: TimeInterval = 120

    enum UserDefaultsKeys {
        static let apiBaseURL = "settings.apiBaseURL"
        static let autoSyncEnabled = "settings.autoSyncEnabled"
        static let syncIntervalMinutes = "settings.syncIntervalMinutes"
        static let matchThreshold = "settings.matchThreshold"
        static let hasSeededMockData = "app.hasSeededMockData"
        static let uploadRawFramesEnabled = "settings.uploadRawFramesEnabled"
        static let faceScanPosePrefix = "settings.faceScan.pose"
        static let faceScanStepPrefix = "settings.faceScan.step"
        static let thresholdMigratedForAdaFace = "settings.thresholdMigratedForAdaFace"
        static let thresholdHardenedLookalike = "settings.thresholdHardenedLookalike"
        static let thresholdRecognitionRetune = "settings.thresholdRecognitionRetune"
        static let supervisorPINEnabled = "settings.supervisorPINEnabled"
        static let supervisorPINHash = "settings.supervisorPINHash"
        static let siteGeofenceEnabled = "settings.siteGeofenceEnabled"
        static let siteLatitude = "settings.siteLatitude"
        static let siteLongitude = "settings.siteLongitude"
        static let siteRadiusMeters = "settings.siteRadiusMeters"
        static let jobSitesJSON = "settings.jobSitesJSON"
        static let defaultJobSiteId = "settings.defaultJobSiteId"
        static let pendingJobSiteDeletions = "sync.pendingJobSiteDeletions"
        static let lastRemoteJobSiteIds = "sync.lastRemoteJobSiteIds"
        static let pendingEmployeeDeletions = "sync.pendingEmployeeDeletions"
        static let clockIntegrityCheckpoint = "settings.clockIntegrityCheckpoint"
    }

    enum Notifications {
        static let attendanceHistoryDidClear = Notification.Name("constrakr.attendanceHistoryDidClear")
        static let employeesDidChange = Notification.Name("constrakr.employeesDidChange")
        static let networkConnectivityDidChange = Notification.Name("constrakr.networkConnectivityDidChange")
    }
}
