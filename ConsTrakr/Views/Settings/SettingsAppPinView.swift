//
//  SettingsAppPinView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsAppPinView: View {
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("New 6-digit PIN", text: $newPin)
                    .keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $confirmPin)
                    .keyboardType(.numberPad)
                Button("Save App PIN") {
                    savePin()
                }
                .disabled(!canSave)
            } header: {
                Text("Local App PIN")
            } footer: {
                Text("Offline PIN separate from the web admin code. Default is 882741 until you change it.")
            }

            if AppPinSettings.hasAppPin {
                Section {
                    Button("Reset to default (882741)", role: .destructive) {
                        AppPinSettings.setPin(AppPinSettings.defaultPin)
                        message = "Reset to default PIN."
                        clearFields()
                    }
                }
            }

            if let message {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("App PIN")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AppPinSettings.ensureDefaultIfNeeded()
        }
    }

    private var canSave: Bool {
        newPin.count == AppPinSettings.pinLength
            && confirmPin == newPin
            && newPin.allSatisfy(\.isNumber)
    }

    private func savePin() {
        guard canSave else {
            message = "PIN must be 6 digits and match confirmation."
            return
        }
        AppPinSettings.setPin(newPin)
        message = "App PIN saved."
        clearFields()
    }

    private func clearFields() {
        newPin = ""
        confirmPin = ""
    }
}
