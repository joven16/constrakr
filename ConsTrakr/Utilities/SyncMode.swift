//
//  SyncMode.swift
//  ConsTrakr
//

import Foundation

/// Controls how much work a sync pass performs.
enum SyncMode {
    /// Pull-to-refresh: push pending data, apply IMS deltas, skip heavy reconcile.
    case quick
    /// Auto-sync, post-registration, Settings: full roster + child-asset reconcile.
    case full
}
