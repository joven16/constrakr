//
//  APITestResult.swift
//  ConsTrakr
//

import Foundation

struct APITestResult {
    let baseURL: String
    let healthURL: String
    let loginURL: String
    let healthOK: Bool
    let healthStatusCode: Int?
    let healthMessage: String
    let loginOK: Bool
    let loginStatusCode: Int?
    let loginMessage: String
    let isPlaceholderHost: Bool

    var summary: String {
        var lines: [String] = []
        lines.append("Base: \(baseURL)")

        if isPlaceholderHost {
            lines.append("⚠️ Placeholder host — set your real server URL in Settings.")
        }

        lines.append("Health \(healthURL): \(healthOK ? "OK" : "FAILED") (\(healthStatusCode.map(String.init) ?? "—"))")
        if !healthMessage.isEmpty {
            lines.append("  \(healthMessage)")
        }

        lines.append("Login \(loginURL): \(loginOK ? "OK" : "FAILED") (\(loginStatusCode.map(String.init) ?? "—"))")
        if !loginMessage.isEmpty {
            lines.append("  \(loginMessage)")
        }

        if healthOK && loginOK {
            lines.append("API ready for sync.")
        } else if !healthOK {
            lines.append("Fix health endpoint first (GET, no auth).")
        } else if loginMessage.contains("invalid_credentials") {
            lines.append("Wrong username or password for sync_admin.")
        } else if loginMessage.contains("Enter username") || loginMessage.contains("Saved session") {
            lines.append("Sign in under Sync account, or enter credentials in Server URL.")
        } else {
            lines.append("Check sync_admin username/password.")
        }

        return lines.joined(separator: "\n")
    }
}

enum APITestRunner {
    @MainActor
    static func run(baseURL: String, username: String, password: String) async -> APITestResult {
        await APIService.shared.updateBaseURL(baseURL)
        await AdminSession.shared.restorePersistedSession()

        let host = normalizedHostRoot(baseURL)
        let healthURL = host + AppConstants.apiPathPrefix + "/health"
        let loginURL = host + AppConstants.apiPathPrefix + "/auth/admin/login"
        let placeholder = host.contains("example.com") || host.contains("your-ims-domain.com") || host.contains("your-server.example.com")

        var healthOK = false
        var healthCode: Int?
        var healthMsg = ""

        do {
            healthOK = try await APIService.shared.healthCheck()
            healthCode = 200
            healthMsg = "Reachable"
        } catch let error as NetworkError {
            switch error {
            case .serverError(let code, let message):
                healthCode = code == 0 ? nil : code
                healthMsg = message ?? "HTTP \(code)"
            default:
                healthMsg = error.localizedDescription
            }
        } catch {
            healthMsg = error.localizedDescription
        }

        var loginOK = false
        var loginCode: Int?
        var loginMsg = ""

        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPassword = !password.isEmpty
        let hasStoredToken = await APIService.shared.hasAuthToken()
        let savedUser = SyncAuthStore.loadUsername()

        if placeholder {
            loginMsg = "Skipped — configure a real server host first."
        } else if hasStoredToken && !hasPassword {
            // Already signed in — password was cleared; verify JWT instead of re-login.
            do {
                try await APIService.shared.verifyAuthSession()
                loginOK = true
                loginCode = 200
                loginMsg = "Saved session valid for \(savedUser ?? trimmedUser)."
            } catch let error as NetworkError {
                switch error {
                case .unauthorized:
                    loginCode = 401
                    loginMsg = "Saved session expired — sign in again under Sync account."
                case .serverError(let code, let message):
                    loginCode = code == 0 ? nil : code
                    loginMsg = message ?? "HTTP \(code)"
                default:
                    loginMsg = error.localizedDescription
                }
            } catch {
                loginMsg = error.localizedDescription
            }
        } else if trimmedUser.isEmpty || !hasPassword {
            loginMsg = "Enter username and password below, or sign in under Sync account first (leave password blank to test saved session)."
        } else {
            do {
                let response = try await APIService.shared.adminLogin(
                    username: trimmedUser,
                    password: password
                )
                loginOK = true
                loginCode = 200
                loginMsg = "Token received (expires \(response.expiresIn.map(String.init) ?? "?")s)"
            } catch let error as NetworkError {
                switch error {
                case .serverError(let code, let message):
                    loginCode = code == 0 ? nil : code
                    loginMsg = message ?? "HTTP \(code)"
                default:
                    loginMsg = error.localizedDescription
                }
            } catch {
                loginMsg = error.localizedDescription
            }
        }

        return APITestResult(
            baseURL: host,
            healthURL: healthURL,
            loginURL: loginURL,
            healthOK: healthOK,
            healthStatusCode: healthCode,
            healthMessage: healthMsg,
            loginOK: loginOK,
            loginStatusCode: loginCode,
            loginMessage: loginMsg,
            isPlaceholderHost: placeholder
        )
    }

    private static func normalizedHostRoot(_ baseURL: String) -> String {
        var base = APIService.previewNormalizedHostRoot(baseURL)
        let suffix = AppConstants.apiPathPrefix
        if base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }
}
