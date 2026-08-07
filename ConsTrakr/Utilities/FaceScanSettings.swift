//
//  FaceScanSettings.swift
//  ConsTrakr
//
//  Live-check steps for Time In / Time Out (attendance scanner), not registration.
//

import Foundation

enum FaceScanSettings {
    static let settingsDidChangeNotification = Notification.Name("constrakr.faceScanSettingsDidChange")

    enum Step: String, CaseIterable, Identifiable {
        case closeUp
        case lookLeft
        case lookRight
        case lookUp
        case lookDown

        var id: String { rawValue }

        var livenessChallenge: LivenessChallenge {
            switch self {
            case .closeUp: return .moveCloser
            case .lookLeft: return .turnLeft
            case .lookRight: return .turnRight
            case .lookUp: return .nodUp
            case .lookDown: return .nodDown
            }
        }

        static let gestureOrder: [Step] = [.lookLeft, .lookRight, .lookUp, .lookDown, .closeUp]
    }

    enum Level: String, CaseIterable, Identifiable {
        case basic
        case standard
        case full

        var id: String { rawValue }

        var title: String {
            switch self {
            case .basic: return "Basic"
            case .standard: return "Standard"
            case .full: return "Full"
            }
        }

        var subtitle: String {
            switch self {
            case .basic: return "Blink + close-up — fastest punch"
            case .standard: return "Blink + left/right + close-up — recommended"
            case .full: return "Blink + all angles + close-up — strongest check"
            }
        }

        var enabledSteps: Set<Step> {
            switch self {
            case .basic: return [.closeUp]
            case .standard: return [.closeUp, .lookLeft, .lookRight]
            case .full: return Set(Step.gestureOrder)
            }
        }
    }

    static func isStepEnabled(_ step: Step) -> Bool {
        let key = storageKey(for: step)
        if UserDefaults.standard.object(forKey: key) == nil {
            return migrateLegacyPoseEnabled(step)
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    @discardableResult
    static func setStepEnabled(_ step: Step, _ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: storageKey(for: step))
        notifySettingsDidChange()
        return true
    }

    static func applyLevel(_ level: Level) {
        for step in Step.gestureOrder {
            UserDefaults.standard.set(level.enabledSteps.contains(step), forKey: storageKey(for: step))
        }
        notifySettingsDidChange()
    }

    static func matchingLevel() -> Level? {
        let current = Set(enabledSteps)
        return Level.allCases.first { $0.enabledSteps == current }
    }

    static var isCustomConfiguration: Bool {
        matchingLevel() == nil
    }

    static var enabledSteps: [Step] {
        Step.gestureOrder.filter { isStepEnabled($0) }
    }

    /// True when every optional gesture toggle is off (blink-only live check).
    static var isBlinkOnlyConfiguration: Bool {
        enabledSteps.isEmpty
    }

    /// Blink is always first; optional gestures follow; 3D confirm is added separately in the scanner.
    static func scannerLivenessSteps() -> [LivenessChallenge] {
        var steps: [LivenessChallenge] = [.blink]
        for step in Step.gestureOrder where step != .closeUp {
            if isStepEnabled(step) {
                steps.append(step.livenessChallenge)
            }
        }
        if isStepEnabled(.closeUp) {
            steps.append(.moveCloser)
        }
        return steps
    }

    static func settingsLabel(for step: Step) -> String {
        switch step {
        case .closeUp: return "Close-up (move closer)"
        case .lookLeft: return "Look left"
        case .lookRight: return "Look right"
        case .lookUp: return "Look up"
        case .lookDown: return "Look down"
        }
    }

    /// Short labels shown on the attendance scanner Ready screen.
    static func stepShortLabel(for step: Step) -> String {
        switch step {
        case .closeUp: return "Close-up"
        case .lookLeft: return "Look left"
        case .lookRight: return "Look right"
        case .lookUp: return "Look up"
        case .lookDown: return "Look down"
        }
    }

    /// Human-readable live-check sequence from current settings (blink + enabled steps + optional 3D).
    static func scannerReadyStepNames(include3D: Bool = true) -> [String] {
        var names = ["Blink"]
        for step in enabledSteps {
            names.append(stepShortLabel(for: step))
        }
        if include3D {
            names.append("3D")
        }
        return names
    }

    /// Preset name or "Custom" for the attendance scanner Ready screen.
    static func scannerPresetLabel() -> String {
        if isBlinkOnlyConfiguration { return "Blink only" }
        return matchingLevel()?.title ?? "Custom"
    }

    /// e.g. "Standard · Blink · Look left · Look right · Close-up · 3D"
    static func scannerReadySummary(extraParts: [String] = []) -> String {
        var segments = [scannerPresetLabel()] + scannerReadyStepNames()
        segments.append(contentsOf: extraParts)
        return segments.joined(separator: " · ")
    }

    private static func storageKey(for step: Step) -> String {
        "\(AppConstants.UserDefaultsKeys.faceScanStepPrefix).\(step.rawValue)"
    }

    private static func notifySettingsDidChange() {
        NotificationCenter.default.post(name: settingsDidChangeNotification, object: nil)
    }

    /// One-time read from older registration-oriented keys (faceScan.pose.*).
    private static func migrateLegacyPoseEnabled(_ step: Step) -> Bool {
        let legacyPose: String = switch step {
        case .closeUp: "center"
        case .lookLeft: "left"
        case .lookRight: "right"
        case .lookUp: "up"
        case .lookDown: "down"
        }
        let legacyKey = "\(AppConstants.UserDefaultsKeys.faceScanPosePrefix).\(legacyPose)"
        if UserDefaults.standard.object(forKey: legacyKey) != nil {
            return UserDefaults.standard.bool(forKey: legacyKey)
        }
        return true
    }
}
