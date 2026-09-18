//
//  RegistrationPoseSettings.swift
//  ConsTrakr
//
//  Face angles captured during employee registration (separate from Time In / Out checks).
//

import Foundation

enum RegistrationPoseSettings {
    static let settingsDidChangeNotification = Notification.Name("constrakr.registrationPoseSettingsDidChange")

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
            case .basic: return "Look straight only — fastest enrollment"
            case .standard: return "Look straight + left/right — recommended"
            case .full: return "All five angles — strongest template"
            }
        }

        var enabledPoses: Set<FacePose> {
            switch self {
            case .basic: return [.center]
            case .standard: return [.center, .left, .right]
            case .full: return Set(FacePose.enrollmentOrder)
            }
        }
    }

    static func isPoseEnabled(_ pose: FacePose) -> Bool {
        let key = storageKey(for: pose)
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    @discardableResult
    static func setPoseEnabled(_ pose: FacePose, _ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: storageKey(for: pose))
        notifySettingsDidChange()
        return true
    }

    static func applyLevel(_ level: Level) {
        for pose in FacePose.enrollmentOrder {
            UserDefaults.standard.set(level.enabledPoses.contains(pose), forKey: storageKey(for: pose))
        }
        notifySettingsDidChange()
    }

    static func applyEnabledPoses(_ enabledByPose: [FacePose: Bool]) {
        var resolved = enabledByPose
        // Enrollment needs at least Look Straight.
        if FacePose.enrollmentOrder.allSatisfy({ resolved[$0] != true }) {
            resolved[.center] = true
        }
        for pose in FacePose.enrollmentOrder {
            UserDefaults.standard.set(resolved[pose] ?? true, forKey: storageKey(for: pose))
        }
        notifySettingsDidChange()
    }

    static func matchingLevel() -> Level? {
        let current = Set(enabledEnrollmentOrder)
        return Level.allCases.first { $0.enabledPoses == current }
    }

    static var isCustomConfiguration: Bool {
        matchingLevel() == nil
    }

    /// Enabled poses in capture order. Always includes at least `.center`.
    static var enabledEnrollmentOrder: [FacePose] {
        let enabled = FacePose.enrollmentOrder.filter { isPoseEnabled($0) }
        return enabled.isEmpty ? [.center] : enabled
    }

    static func settingsLabel(for pose: FacePose) -> String {
        pose.displayName
    }

    private static func storageKey(for pose: FacePose) -> String {
        "\(AppConstants.UserDefaultsKeys.registrationPosePrefix).\(pose.rawValue)"
    }

    private static func notifySettingsDidChange() {
        NotificationCenter.default.post(name: settingsDidChangeNotification, object: nil)
    }
}
