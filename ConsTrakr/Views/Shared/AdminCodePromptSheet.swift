//
//  AdminCodePromptSheet.swift
//  ConsTrakr
//

import SwiftUI

struct AdminCodePromptSheet: View {
    let title: String
    let message: String
    let onConfirm: (String) async throws -> Void
    let onCancel: () -> Void

    var body: some View {
        PasscodeKeypadView(
            title: title,
            subtitle: promptSubtitle,
            onSubmit: onConfirm,
            onCancel: onCancel
        )
    }

    private var promptSubtitle: String {
        let labels = DeviceStore.assignedUserLabels
        if labels.count == 1 {
            return "\(message)\n\nUse the 6-digit admin code for \(labels[0])."
        }
        if labels.count > 1 {
            let joined = labels.joined(separator: ", ")
            return "\(message)\n\nUse the 6-digit admin code for any assigned user: \(joined)."
        }
        return "\(message)\n\nUse the 6-digit admin code from a user assigned to this device on the web dashboard."
    }
}
