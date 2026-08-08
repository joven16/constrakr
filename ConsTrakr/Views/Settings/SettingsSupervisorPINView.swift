//
//  SettingsSupervisorPINView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsSupervisorPINView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Require supervisor PIN", isOn: $viewModel.supervisorPINEnabled)
            } footer: {
                Text("When enabled, Time In / Time Out asks for a supervisor PIN before the camera scan.")
            }

            Section {
                SecureField("New PIN (4–12 digits)", text: $viewModel.newSupervisorPIN)
                    .keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $viewModel.confirmSupervisorPIN)
                    .keyboardType(.numberPad)
                Button("Save PIN") {
                    viewModel.saveSupervisorPIN()
                }
                .disabled(viewModel.newSupervisorPIN.count < 4)
                if SupervisorPINSettings.hasPIN {
                    Button("Clear PIN", role: .destructive) {
                        viewModel.clearSupervisorPIN()
                    }
                }
            } header: {
                Text("PIN")
            }
        }
        .navigationTitle("Supervisor PIN")
        .navigationBarTitleDisplayMode(.inline)
    }
}
