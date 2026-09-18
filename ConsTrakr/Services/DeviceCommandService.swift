//
//  DeviceCommandService.swift
//  ConsTrakr
//

import Foundation

@MainActor
final class DeviceCommandService {
    static let shared = DeviceCommandService()

    private let lastHandledKey = "deviceCommands.lastPlaySoundId"
    private var isHandling = false
    private(set) var lastErrorMessage: String?

    func pollRemoteCommands() async {
        guard AdminSession.shared.isAuthenticated else { return }
        guard await APIService.shared.hasAuthToken() else { return }
        do {
            _ = try await APIService.shared.registerDevice(
                localId: DeviceStore.localId,
                name: DeviceStore.syncName,
                appVersion: DeviceStore.appVersion
            )
            guard let device = try await APIService.shared.fetchDevice(localId: DeviceStore.localId) else {
                lastErrorMessage = "Device not found on server."
                return
            }
            DeviceStore.update(from: device)
            lastErrorMessage = nil
            await handle(device: device)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func handle(device: DeviceDTO) async {
        guard let requestId = device.playSoundRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestId.isEmpty else { return }
        guard !isHandling else { return }
        let last = UserDefaults.standard.string(forKey: lastHandledKey)
        guard requestId != last else { return }

        isHandling = true
        defer { isHandling = false }

        do {
            try await APIService.shared.ackDevicePlaySound(requestId: requestId, stage: "ringing")
            DeviceFindAlarmPlayer.shared.playFor()
            try await APIService.shared.ackDevicePlaySound(requestId: requestId, stage: "completed")
            UserDefaults.standard.set(requestId, forKey: lastHandledKey)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            DeviceFindAlarmPlayer.shared.stop()
        }
    }
}
