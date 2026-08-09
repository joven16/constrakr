//
//  ToggleBusyCenter.swift
//  ConsTrakr
//

import SwiftUI

@MainActor
@Observable
final class ToggleBusyCenter {
    static let shared = ToggleBusyCenter()

    private(set) var isBusy = false
    private var hideTask: Task<Void, Never>?

    func flash(durationNanoseconds: UInt64 = 550_000_000) {
        isBusy = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else { return }
            self?.isBusy = false
        }
    }
}

extension Binding where Value == Bool {
    /// Shows the app-wide center spinner whenever this toggle binding is written.
    func withToggleBusy() -> Binding<Bool> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                ToggleBusyCenter.shared.flash()
                wrappedValue = newValue
            }
        )
    }
}

struct ToggleBusyOverlay: ViewModifier {
    @State private var busy = ToggleBusyCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if busy.isBusy {
                    ZStack {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color(.systemGray))
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: busy.isBusy)
    }
}

extension View {
    func toggleBusyOverlay() -> some View {
        modifier(ToggleBusyOverlay())
    }
}
