//
//  NetworkMonitor.swift
//  ConsTrakr
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = false
    private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.constrakr.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connected = path.status == .satisfied
                let type: NWInterface.InterfaceType?
                if path.usesInterfaceType(.wifi) {
                    type = .wifi
                } else if path.usesInterfaceType(.wiredEthernet) {
                    type = .wiredEthernet
                } else if path.usesInterfaceType(.cellular) {
                    type = .cellular
                } else {
                    type = path.availableInterfaces.first?.type
                }
                let changed = isConnected != connected || connectionType != type
                isConnected = connected
                connectionType = type
                if changed {
                    NotificationCenter.default.post(
                        name: AppConstants.Notifications.networkConnectivityDidChange,
                        object: nil
                    )
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var isOnWiFi: Bool {
        guard isConnected else { return false }
        switch connectionType {
        case .wifi, .wiredEthernet:
            return true
        default:
            return false
        }
    }

    var isOnCellular: Bool {
        guard isConnected else { return false }
        return connectionType == .cellular
    }

    /// SF Symbol for the current connection: Wi‑Fi, cellular signal, or offline.
    var statusSymbolName: String {
        guard isConnected else { return "wifi.slash" }
        if isOnWiFi { return "wifi" }
        if isOnCellular { return "antenna.radiowaves.left.and.right" }
        return "network"
    }

    var statusAccessibilityLabel: String {
        guard isConnected else { return "Offline" }
        if isOnWiFi { return "Wi‑Fi" }
        if isOnCellular { return "Cellular data" }
        return "Online"
    }
}
