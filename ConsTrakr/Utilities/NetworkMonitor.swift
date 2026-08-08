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
                let changed = isConnected != connected
                isConnected = connected
                connectionType = path.availableInterfaces.first?.type
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
}
