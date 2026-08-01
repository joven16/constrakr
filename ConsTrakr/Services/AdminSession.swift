//
//  AdminSession.swift
//  ConsTrakr
//
//  CHANGE: Lightweight admin auth gate for restore-on-new-device.
//  INTEGRATION: Replace demo login with your real identity provider.
//

import Foundation

@MainActor
@Observable
final class AdminSession {
    static let shared = AdminSession()

    private(set) var isAuthenticated = false
    private(set) var username: String?

    private init() {}

    func signIn(username: String, password: String) async throws {
        let response = try await APIService.shared.adminLogin(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        await APIService.shared.setAuthToken(response.accessToken)
        self.username = username
        self.isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        username = nil
        Task { await APIService.shared.setAuthToken(nil) }
    }
}
