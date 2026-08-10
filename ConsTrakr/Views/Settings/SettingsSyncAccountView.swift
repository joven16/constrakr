//
//  SettingsSyncAccountView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsSyncAccountView: View {
    @Environment(SyncQueue.self) private var syncQueue
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            Section {
                if viewModel.isAdminAuthenticated {
                    LabeledContent("Signed in as", value: AdminSession.shared.username ?? "Admin")
                    Button("Sign out", role: .destructive) {
                        viewModel.signOutAdmin()
                    }
                } else {
                    TextField("Admin username", text: $viewModel.adminUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(viewModel.isSigningIn)
                    SecureField("Password", text: $viewModel.adminPassword)
                        .disabled(viewModel.isSigningIn)
                    if viewModel.isSigningIn {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Color(.systemGray))
                            Spacer()
                        }
                    } else {
                        Button("Sign in") {
                            Task { await viewModel.signInAdmin() }
                        }
                        .disabled(viewModel.adminUsername.isEmpty || viewModel.adminPassword.isEmpty)
                    }
                    if let signInError = viewModel.signInError {
                        Text(signInError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } footer: {
                Text("Use your sync account to upload attendance and employees to the server.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sync Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await AdminSession.shared.restorePersistedSession()
            viewModel.configure(syncQueue: syncQueue)
        }
    }
}
