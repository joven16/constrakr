//
//  PendingEmployeeDeletionStore.swift
//  ConsTrakr
//
//  Queues IMS soft-deletes when an employee is removed on device while offline.
//

import Foundation

enum PendingEmployeeDeletionStore {
    private static let storageKey = AppConstants.UserDefaultsKeys.pendingEmployeeDeletions

    static func pendingServerIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    static func enqueue(serverId: String) {
        let normalized = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var ids = Set(pendingServerIds())
        ids.insert(normalized)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: storageKey)
    }

    static func remove(serverId: String) {
        let normalized = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var ids = Set(pendingServerIds())
        ids.remove(normalized)
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else {
            UserDefaults.standard.set(Array(ids).sorted(), forKey: storageKey)
        }
    }

    static func hasPending() -> Bool {
        !pendingServerIds().isEmpty
    }
}
