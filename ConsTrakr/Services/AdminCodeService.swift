//
//  AdminCodeService.swift
//  ConsTrakr
//

import Foundation

enum AdminCodeError: LocalizedError {
    case offline
    case notRegistered
    case noAssignedUser
    case adminCodeNotSet
    case invalidPasscode
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Connect to the server to verify the admin code."
        case .notRegistered:
            return "This device is not registered yet. Sign in and sync first."
        case .noAssignedUser:
            return "No users are assigned to this device. Assign one or more under Devices on the web dashboard."
        case .adminCodeNotSet:
            return "None of the assigned users has set a 6-digit admin code. They can set it under Profile → Edit Profile."
        case .invalidPasscode:
            return "Incorrect admin code."
        case .serverMessage(let message):
            return message
        }
    }
}

@MainActor
enum AdminCodeService {
    static func ensureChangeAllowed() throws {
        guard DeviceStore.hasAssignedUsers else {
            throw AdminCodeError.noAssignedUser
        }
        guard DeviceStore.adminCodeRequired else {
            throw AdminCodeError.adminCodeNotSet
        }
    }

    static func verify(passcode: String) async throws {
        guard passcode.count == AdminCodeConstants.digitCount, passcode.allSatisfy(\.isNumber) else {
            throw AdminCodeError.invalidPasscode
        }
        guard NetworkMonitor.shared.isConnected else {
            throw AdminCodeError.offline
        }
        try ensureChangeAllowed()

        let response = try await APIService.shared.verifyDeviceAdminCode(
            localId: DeviceStore.localId,
            passcode: passcode
        )
        guard response.valid else {
            if let error = response.error {
                switch error {
                case "invalid_passcode":
                    throw AdminCodeError.invalidPasscode
                case "no_assigned_user":
                    throw AdminCodeError.noAssignedUser
                case "admin_code_not_set":
                    throw AdminCodeError.adminCodeNotSet
                case "device_not_registered":
                    throw AdminCodeError.notRegistered
                default:
                    throw AdminCodeError.serverMessage(response.errorMessage ?? "Verification failed.")
                }
            }
            throw AdminCodeError.invalidPasscode
        }
        if let name = response.assignedUserName {
            UserDefaults.standard.set(name, forKey: AppConstants.UserDefaultsKeys.deviceAssignedUserName)
        }
    }
}
