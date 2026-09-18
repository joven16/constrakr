//
//  DeviceTrackingCollector.swift
//  ConsTrakr
//

import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum DeviceTrackingCollector {
    struct Snapshot {
        let payload: DeviceHeartbeatPayload
        let hadLocation: Bool
    }

    static func collectSnapshot() async -> Snapshot {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let battery = readBattery()
        let location = await readLocationOnce()
        let online = NetworkMonitor.shared.isConnected

        let payload = DeviceHeartbeatPayload(
            id: UUID(),
            deviceId: DeviceStore.localId,
            siteId: JobSiteStore.defaultSiteId?.uuidString,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            accuracyMeters: location.map { Float($0.horizontalAccuracy) },
            batteryPercent: battery.percent,
            isCharging: battery.charging,
            networkType: readNetworkType(),
            isOnline: online,
            isKioskModeActive: false,
            deviceModel: deviceModelName(),
            platform: "ios",
            iosVersion: iosVersionString(),
            androidVersion: "",
            appVersion: DeviceStore.appVersion,
            timestamp: now,
            syncStatus: "pending"
        )
        return Snapshot(payload: payload, hadLocation: location != nil)
    }

    private static func readBattery() -> (percent: Int, charging: Bool) {
#if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let percent = level < 0 ? -1 : Int((level * 100).rounded())
        let state = UIDevice.current.batteryState
        let charging = state == .charging || state == .full
        return (percent, charging)
#else
        return (-1, false)
#endif
    }

    private static func readNetworkType() -> String? {
        NetworkMonitor.shared.isConnected ? "wifi_or_cellular" : "none"
    }

    private static func deviceModelName() -> String {
#if canImport(UIKit)
        var systemInfo = utsname()
        uname(&systemInfo)
        let code = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "iPhone"
            }
        }
        return code
#else
        return "iOS"
#endif
    }

    private static func iosVersionString() -> String {
#if canImport(UIKit)
        UIDevice.current.systemVersion
#else
        ""
#endif
    }

    private static func readLocationOnce() async -> CLLocation? {
        await SiteLocationGate().oneShotLocationForTracking(
            maxAccuracyMeters: DeviceTrackingConfig.maxGPSAccuracyMeters
        )
    }
}
