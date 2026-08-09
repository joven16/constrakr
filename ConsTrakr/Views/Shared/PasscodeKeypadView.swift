//
//  PasscodeKeypadView.swift
//  ConsTrakr
//
//  Layout and styling aligned to iOS Settings / Lock Screen passcode entry.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PasscodeKeypadView: View {
    let title: String
    let subtitle: String
    var minDigits: Int = AdminCodeConstants.digitCount
    var maxDigits: Int = AdminCodeConstants.digitCount
    let onSubmit: (String) async throws -> Void
    let onCancel: () -> Void

    @State private var digits = ""
    @State private var errorMessage: String?
    @State private var isVerifying = false
    @State private var shakeOffset: CGFloat = 0
    @State private var hapticTick = 0

    /// Native passcode key diameter on modern iPhones.
    private let keySize: CGFloat = 84
    private let rowSpacing: CGFloat = 16
    private let columnSpacing: CGFloat = 24

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 0)

                VStack(spacing: 28) {
                    VStack(spacing: 0) {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.regular)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 32)

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .padding(.top, 8)
                        }

                        passcodeDots
                            .padding(.top, 24)
                            .offset(x: shakeOffset)

                        statusLine
                            .padding(.top, 14)
                            .frame(minHeight: 22)
                    }

                    VStack(spacing: 20) {
                        keypad
                            .fixedSize(horizontal: true, vertical: true)

                        if isVerifying {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
        }
        .interactiveDismissDisabled(isVerifying)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
    }

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .disabled(isVerifying)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var passcodeDots: some View {
        HStack(spacing: 16) {
            ForEach(0..<maxDigits, id: \.self) { index in
                Circle()
                    .fill(index < digits.count ? Color.primary : Color.clear)
                    .overlay {
                        if index >= digits.count {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 12, height: 12)
            }
        }
        .animation(.easeOut(duration: 0.1), value: digits.count)
        .accessibilityLabel("\(digits.count) of \(maxDigits) digits entered")
    }

    private var keypad: some View {
        VStack(spacing: rowSpacing) {
            keypadRow(["1", "2", "3"])
            keypadRow(["4", "5", "6"])
            keypadRow(["7", "8", "9"])
            HStack(spacing: columnSpacing) {
                Color.clear
                    .frame(width: keySize, height: keySize)
                    .accessibilityHidden(true)
                digitKey("0") { appendDigit("0") }
                deleteKey
            }
        }
    }

    private func keypadRow(_ labels: [String]) -> some View {
        HStack(spacing: columnSpacing) {
            ForEach(labels, id: \.self) { label in
                digitKey(label) { appendDigit(label) }
            }
        }
    }

    private func digitKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 36, weight: .light))
                .frame(width: keySize, height: keySize)
                .contentShape(Circle())
        }
        .buttonStyle(PasscodeDigitKeyStyle())
        .disabled(isVerifying)
    }

    private var deleteKey: some View {
        Button(action: deleteDigit) {
            Image(systemName: "delete.left")
                .font(.system(size: 23, weight: .regular))
                .frame(width: keySize, height: keySize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PasscodeDeleteKeyStyle())
        .disabled(digits.isEmpty || isVerifying)
        .opacity(digits.isEmpty ? 0.35 : 1)
    }

    private func appendDigit(_ digit: String) {
        guard digits.count < maxDigits, !isVerifying else { return }
        hapticTick += 1
        errorMessage = nil
        digits.append(digit)
        if digits.count == maxDigits {
            Task { await submit() }
        }
    }

    private func deleteDigit() {
        guard !digits.isEmpty, !isVerifying else { return }
        hapticTick += 1
        errorMessage = nil
        digits.removeLast()
    }

    private func submit() async {
        guard digits.count == maxDigits, !isVerifying else { return }
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        do {
            try await onSubmit(digits)
        } catch {
            playErrorFeedback()
            await shakeDots()
            errorMessage = error.localizedDescription
            digits = ""
        }
    }

    private func shakeDots() async {
        let offsets: [CGFloat] = [14, -14, 10, -10, 0]
        for offset in offsets {
            withAnimation(.easeInOut(duration: 0.08)) {
                shakeOffset = offset
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private func playErrorFeedback() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

// MARK: - iOS-style key press styles

private struct PasscodeDigitKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .opacity(configuration.isPressed ? 0.55 : 1)
            }
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.16), value: configuration.isPressed)
    }
}

private struct PasscodeDeleteKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.45 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.16), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    PasscodeKeypadView(
        title: "Enter Passcode",
        subtitle: "Enter the admin code to continue.",
        onSubmit: { _ in },
        onCancel: {}
    )
}
#endif
