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

    private let keypadColumns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 24)

                header

                passcodeDots
                    .padding(.top, 28)
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
                .padding(.top, 8)
                .frame(minHeight: 22)

                Spacer(minLength: 24)

                keypad
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)

                if isVerifying {
                    ProgressView()
                        .padding(.bottom, 28)
                } else {
                    Color.clear
                        .frame(height: 28)
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
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private var passcodeDots: some View {
        HStack(spacing: 14) {
            ForEach(0..<maxDigits, id: \.self) { index in
                Circle()
                    .fill(index < digits.count ? Color.primary : Color.clear)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(index < digits.count ? 0 : 0.35), lineWidth: 1.5)
                    }
                    .frame(width: 13, height: 13)
            }
        }
        .animation(.easeOut(duration: 0.12), value: digits.count)
        .accessibilityLabel("\(digits.count) of \(maxDigits) digits entered")
    }

    private var keypad: some View {
        LazyVGrid(columns: keypadColumns, spacing: 18) {
            ForEach(1...9, id: \.self) { digit in
                keypadDigit("\(digit)") {
                    appendDigit("\(digit)")
                }
            }

            Color.clear
                .frame(height: 76)

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
                .font(.system(size: 32, weight: .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background {
                    Circle()
                        .fill(Color(.systemGray5))
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
                .frame(height: 76)
                .background {
                    Circle()
                        .fill(Color(.systemGray5))
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
