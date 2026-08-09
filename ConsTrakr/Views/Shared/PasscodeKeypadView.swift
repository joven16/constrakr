//
//  PasscodeKeypadView.swift
//  ConsTrakr
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

    private let keypadColumns = Array(repeating: GridItem(.flexible(), spacing: 22), count: 3)

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 28)

                header

                passcodeDots
                    .padding(.top, 32)
                    .offset(x: shakeOffset)

                Group {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text(" ")
                    }
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .frame(minHeight: 22)

                Spacer(minLength: 28)

                keypad
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                if isVerifying {
                    ProgressView()
                        .padding(.bottom, 32)
                } else {
                    Color.clear
                        .frame(height: 32)
                }
            }
        }
        .interactiveDismissDisabled(isVerifying)
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .font(.body)
            .disabled(isVerifying)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var passcodeDots: some View {
        HStack(spacing: 16) {
            ForEach(0..<maxDigits, id: \.self) { index in
                Circle()
                    .fill(index < digits.count ? Color.primary : Color.clear)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(index < digits.count ? 0 : 0.35), lineWidth: 1.5)
                    }
                    .frame(width: 14, height: 14)
            }
        }
        .animation(.easeOut(duration: 0.12), value: digits.count)
        .accessibilityLabel("\(digits.count) of \(maxDigits) digits entered")
    }

    private var keypad: some View {
        LazyVGrid(columns: keypadColumns, spacing: 16) {
            ForEach(1...9, id: \.self) { digit in
                keypadDigit("\(digit)") {
                    appendDigit("\(digit)")
                }
            }

            Color.clear
                .frame(height: 80)

            keypadDigit("0") {
                appendDigit("0")
            }

            keypadIcon("delete.left.fill") {
                deleteDigit()
            }
            .foregroundStyle(.primary)
        }
    }

    private func keypadDigit(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.07))
                }
        }
        .buttonStyle(.plain)
        .disabled(isVerifying)
    }

    private func keypadIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.regular))
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.07))
                }
        }
        .buttonStyle(.plain)
        .disabled(isVerifying)
    }

    private func appendDigit(_ digit: String) {
        guard digits.count < maxDigits, !isVerifying else { return }
        playKeyTap()
        errorMessage = nil
        digits.append(digit)
        if digits.count == maxDigits {
            Task { await submit() }
        }
    }

    private func deleteDigit() {
        guard !digits.isEmpty, !isVerifying else { return }
        playKeyTap()
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
        let steps: [CGFloat] = [0, -12, 12, -10, 10, -6, 6, 0]
        for step in steps {
            shakeOffset = step
            try? await Task.sleep(for: .milliseconds(45))
        }
    }

    private func playKeyTap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func playErrorFeedback() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
