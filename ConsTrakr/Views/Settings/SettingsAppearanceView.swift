//
//  SettingsAppearanceView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsAppearanceView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.appTheme) private var appThemeRaw = AppTheme.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appThemeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("System follows your iPhone light or dark mode. Light and dark override it for this app only.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
