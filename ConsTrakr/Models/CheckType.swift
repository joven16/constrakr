//
//  CheckType.swift
//  ConsTrakr
//

import Foundation

enum CheckType: String, Codable, CaseIterable, Identifiable {
    case checkIn = "check_in"
    case checkOut = "check_out"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checkIn: return "Time In"
        case .checkOut: return "Time Out"
        }
    }

    var confirmPrompt: String {
        switch self {
        case .checkIn: return "Confirm Time In?"
        case .checkOut: return "Confirm Time Out?"
        }
    }

    var confirmMessage: String {
        switch self {
        case .checkIn: return "Start face scanning to record Time In for the recognized employee."
        case .checkOut: return "Start face scanning to record Time Out for the recognized employee."
        }
    }

    var systemImage: String {
        switch self {
        case .checkIn: return "arrow.down.circle.fill"
        case .checkOut: return "arrow.up.circle.fill"
        }
    }
}
