//
//  AdminCodePromptSheet.swift
//  ConsTrakr
//

import SwiftUI

struct AdminCodePromptSheet: View {
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: (String) async throws -> Void
    let onCancel: () -> Void

    @State private var passcode = ""
    @State private var errorMessage: String?
    @State private var isVerifying = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField("Admin code", text: $passcode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isFieldFocused)
                } footer: {
                    if let assigned = DeviceStore.assignedUserName ?? DeviceStore.assignedUserUsername {
                        Text("Use the admin code for \(assigned).")
                    } else {
                        Text("Use the admin code from the user assigned to this device in IMS.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isVerifying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) {
                        Task { await submit() }
                    }
                    .disabled(passcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                }
            }
            .onAppear {
                isFieldFocused = true
            }
            .interactiveDismissDisabled(isVerifying)
        }
    }

    private func submit() async {
        let code = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Admin code is required."
            return
        }
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            try await onConfirm(code)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
