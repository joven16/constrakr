//
//  DeviceBlockedView.swift
//  ConsTrakr
//

import SwiftUI

struct DeviceBlockedView: View {
    @Environment(SyncQueue.self) private var syncQueue
    @State private var isChecking = false
    @State private var checkMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)

                Text("Device disabled")
                    .font(.title2.weight(.semibold))

                Text(DeviceAccessGuard.blockedMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Attendance scanning, employee changes, and cloud sync are turned off on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if let checkMessage {
                    Text(checkMessage)
                        .font(.caption)
                        .foregroundStyle(checkMessage.contains("still") ? .orange : .green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    Task { await checkAgain() }
                } label: {
                    if isChecking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Check again")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking)
                .padding(.horizontal, 40)
                .padding(.top, 8)

                LabeledContent("Device ID") {
                    Text(DeviceStore.localId.uuidString)
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 40)
                .padding(.top, 12)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func checkAgain() async {
        isChecking = true
        checkMessage = nil
        defer { isChecking = false }

        await syncQueue.refreshDeviceAccessStatus()

        if DeviceStore.isBlocked {
            checkMessage = "This device is still disabled."
        } else {
            checkMessage = "Access restored. You can use the app again."
        }
    }
}
