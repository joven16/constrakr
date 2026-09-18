//
//  DeviceHeartbeatStore.swift
//  ConsTrakr
//

import Foundation

struct DeviceHeartbeatPayload: Codable, Identifiable {
    let id: UUID
    let deviceId: UUID
    let siteId: String?
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Float?
    let batteryPercent: Int
    let isCharging: Bool
    let networkType: String?
    let isOnline: Bool
    let isKioskModeActive: Bool
    let deviceModel: String
    let platform: String
    let iosVersion: String
    let androidVersion: String
    let appVersion: String
    let timestamp: Int64
    var syncStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case siteId = "site_id"
        case latitude
        case longitude
        case accuracyMeters = "accuracy_meters"
        case batteryPercent = "battery_percent"
        case isCharging = "is_charging"
        case networkType = "network_type"
        case isOnline = "is_online"
        case isKioskModeActive = "is_kiosk_mode_active"
        case deviceModel = "device_model"
        case platform
        case iosVersion = "ios_version"
        case androidVersion = "android_version"
        case appVersion = "app_version"
        case timestamp
        case syncStatus = "sync_status"
    }

    func apiBody() -> DeviceHeartbeatRequest {
        DeviceHeartbeatRequest(
            deviceId: deviceId,
            siteId: siteId,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracyMeters,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            networkType: networkType,
            isOnline: isOnline,
            isKioskModeActive: isKioskModeActive,
            deviceModel: deviceModel,
            platform: platform,
            iosVersion: iosVersion,
            androidVersion: androidVersion,
            appVersion: appVersion,
            timestamp: timestamp
        )
    }
}

enum DeviceHeartbeatStore {
    private static let queueFileName = "device_heartbeats.json"
    private static let lock = NSLock()

    static func pending() -> [DeviceHeartbeatPayload] {
        lock.lock()
        defer { lock.unlock() }
        return loadAll().filter { $0.syncStatus == "pending" }
    }

    static func pendingCount() -> Int {
        pending().count
    }

    static func latest() -> DeviceHeartbeatPayload? {
        lock.lock()
        defer { lock.unlock() }
        return loadAll().max(by: { $0.timestamp < $1.timestamp })
    }

    @discardableResult
    static func enqueue(_ payload: DeviceHeartbeatPayload) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var rows = loadAll()
        if rows.contains(where: { $0.id == payload.id }) { return false }
        rows.append(payload)
        save(rows)
        return true
    }

    static func markSynced(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var rows = loadAll()
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].syncStatus = "synced"
        save(rows)
        pruneSynced()
    }

    private static func pruneSynced() {
        let cutoff = Int64(Date().addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970 * 1000)
        let rows = loadAll().filter { row in
            row.syncStatus != "synced" || row.timestamp >= cutoff
        }
        save(rows)
    }

    private static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ConsTrakr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(queueFileName)
    }

    private static func loadAll() -> [DeviceHeartbeatPayload] {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DeviceHeartbeatPayload].self, from: data)) ?? []
    }

    private static func save(_ rows: [DeviceHeartbeatPayload]) {
        let url = fileURL()
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
