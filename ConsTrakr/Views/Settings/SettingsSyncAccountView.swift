//
//  SettingsSyncAccountView.swift
//  ConsTrakr
//

import SwiftUI

struct SettingsSyncAccountView: View {
    @Environment(SyncQueue.self) private var syncQueue
    @State private var viewModel = SettingsViewModel()
    @State private var showAdminCodePrompt = false
    @State private var adminGateError: String?

    var body: some View {
        List {
            Section {
                if viewModel.isAdminAuthenticated {
                    LabeledContent("Signed in as", value: AdminSession.shared.username ?? "Admin")
                    Button("Sign out", role: .destructive) {
                        requestSignOut()
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
                if let adminGateError {
                    Text(adminGateError)
                        .foregroundStyle(.red)
                } else {
                    Text("Use your sync account to upload attendance and employees to the server. Signing out requires the device admin code.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sync Account")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: DeviceStore.deviceDidChangeNotification)) { _ in
            adminGateError = nil
        }
        .fullScreenCover(isPresented: $showAdminCodePrompt) {
            AdminCodePromptSheet(
                title: "Sign out",
                message: "Enter the admin code to sign out of the sync account on this device.",
                onConfirm: { code in
                    try await AdminCodeService.verify(passcode: code)
                    viewModel.signOutAdmin()
                    showAdminCodePrompt = false
                    adminGateError = nil
                },
                onCancel: {
                    showAdminCodePrompt = false
                }
            )
        }
        .task {
            await AdminSession.shared.restorePersistedSession()
            viewModel.configure(syncQueue: syncQueue)
        }
    }

    private func requestSignOut() {
        adminGateError = nil
        do {
            try AdminCodeService.ensureChangeAllowed()
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }
}
