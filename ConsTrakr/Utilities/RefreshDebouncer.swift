//
//  RefreshDebouncer.swift
//  ConsTrakr
//

import Foundation

@MainActor
final class RefreshDebouncer {
    private var task: Task<Void, Never>?
    private let delayNanoseconds: UInt64

    init(delayMilliseconds: Int = 250) {
        delayNanoseconds = UInt64(max(0, delayMilliseconds)) * 1_000_000
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
