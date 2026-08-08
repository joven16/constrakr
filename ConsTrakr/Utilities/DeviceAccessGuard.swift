//
//  DeviceAccessGuard.swift
//  ConsTrakr
//

import Foundation

enum DeviceAccessError: LocalizedError {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let message):
            return message
        }
    }
}

enum DeviceAccessGuard {
    static var isBlocked: Bool {
        DeviceStore.isBlocked
    }

    static var blockedMessage: String {
        let reason = DeviceStore.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason, !reason.isEmpty {
            return reason
        }
        return "This device has been disabled by your administrator. Contact them to restore access."
    }

    static func ensureAllowed() throws {
        guard !isBlocked else {
            throw DeviceAccessError.blocked(blockedMessage)
        }
    }
}
