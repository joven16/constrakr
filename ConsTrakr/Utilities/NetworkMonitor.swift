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
            Task { @MainActor in
                let connected = path.status == .satisfied
                let changed = self?.isConnected != connected
                self?.isConnected = connected
                self?.connectionType = path.availableInterfaces.first?.type
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
}
