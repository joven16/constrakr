//
//  NetworkError.swift
//  ConsTrakr
//

import Foundation

enum NetworkError: LocalizedError {
    case offline
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String?)
    case decodingFailed(message: String? = nil)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .offline:
            return Self.offlineMessage
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .unauthorized:
            return "Sign in under Settings with your sync admin account before syncing."
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))."
        case .decodingFailed(let message):
            return message ?? "Failed to decode server response."
        case .encodingFailed:
            return "Failed to encode request body."
        }
    }

    static let offlineMessage = "No internet connection. Records will sync later."

    static func isOfflineMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        return message == offlineMessage
    }
}
