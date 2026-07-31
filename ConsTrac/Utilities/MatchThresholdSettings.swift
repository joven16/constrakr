//
//  MatchThresholdSettings.swift
//  ConsTrac
//

import Foundation

enum MatchThresholdSettings {
    static var current: Float {
        migrateIfNeeded()
        let stored = UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.matchThreshold)
        if stored > 0 { return Float(stored) }
        return recommendedDefault
    }

    static var margin: Float { AppConstants.faceMatchMargin }

    static var soloFloor: Float {
        CoreMLFaceRecognizer.shared.isReady
            ? AppConstants.adaFaceSoloGalleryThreshold
            : AppConstants.soloGalleryMatchThreshold
    }

    static var recommendedDefault: Float {
        CoreMLFaceRecognizer.shared.isReady
            ? AppConstants.adaFaceMatchThreshold
            : AppConstants.faceMatchThreshold
    }

    static var engineName: String {
        CoreMLFaceRecognizer.shared.isReady ? "AdaFace IR-18 (Core ML)" : "Handcrafted fallback"
    }

    private static func migrateIfNeeded() {
        let flag = AppConstants.UserDefaultsKeys.thresholdMigratedForAdaFace
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        defer { UserDefaults.standard.set(true, forKey: flag) }

        // Old builds stored 0.85–0.99 thresholds for handcrafted vectors — far too high for AdaFace.
        guard CoreMLFaceRecognizer.shared.isReady else { return }
        let stored = UserDefaults.standard.double(forKey: AppConstants.UserDefaultsKeys.matchThreshold)
        if stored <= 0 || stored >= 0.80 {
            UserDefaults.standard.set(
                Double(AppConstants.adaFaceMatchThreshold),
                forKey: AppConstants.UserDefaultsKeys.matchThreshold
            )
        }
    }
}
