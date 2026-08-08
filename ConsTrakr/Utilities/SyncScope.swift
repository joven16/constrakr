//
//  SyncScope.swift
//  ConsTrakr
//

import Foundation

/// Which data a sync pass should touch.
enum SyncScope {
    /// Roster, employees, face data — skips attendance upload.
    case employees
    /// Pending Time In / Time Out punches only.
    case attendance
    /// Full pipeline (auto-sync, Settings full sync, post-registration).
    case all
}
