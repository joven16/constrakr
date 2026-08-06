//
//  AdminSession.swift
//  ConsTrakr
//
//  IMS admin auth for sync + cloud restore (`POST /constrakr-api/auth/admin/login`).
//

import Foundation

@MainActor
@Observable
final class AdminSession {
    static let shared = AdminSession()

    private(set) var isAuthenticated = false
    private(set) var username: String?

    private init() {}

    func restorePersistedSession() async {
        guard let token = SyncAuthStore.loadToken() else { return }
        if SyncAuthStore.isTokenExpired() {
            handleUnauthorized()
            return
        }
        await APIService.shared.setAuthToken(token)
        username = SyncAuthStore.loadUsername()
        isAuthenticated = true
    }

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
        SyncAuthStore.clear()
        Task { await APIService.shared.setAuthToken(nil) }
    }

    func handleUnauthorized() {
        isAuthenticated = false
        username = nil
        Task { await APIService.shared.setAuthToken(nil) }
    }
}
