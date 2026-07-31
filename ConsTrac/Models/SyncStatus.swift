//
//  SyncStatus.swift
//  ConsTrac
//

import Foundation
import SwiftUI

enum SyncStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case syncing
    case synced
    case failed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .failed: return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .syncing: return .blue
        case .synced: return .green
        case .failed: return .red
        }
    }
}
