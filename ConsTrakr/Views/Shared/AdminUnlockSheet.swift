//
//  AdminUnlockSheet.swift
//  ConsTrakr
//

import SwiftUI

struct AdminUnlockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppAccessSession.self) private var access

    var body: some View {
        AdminCodePromptSheet(
            title: "Unlock admin",
            message: "Enter the admin code to manage job sites, settings, and delete employees.",
            onConfirm: { code in
                try await AdminCodeService.verify(passcode: code)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}
