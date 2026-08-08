//
//  AppThemeSettings.swift
//  ConsTrakr
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppThemeSettings {
    static var selected: AppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.appTheme),
                  let theme = AppTheme(rawValue: raw) else {
                return .system
            }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppConstants.UserDefaultsKeys.appTheme)
        }
    }
}
