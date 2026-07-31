//
//  NetworkError.swift
//  ConsTrac
//

import Foundation

enum NetworkError: LocalizedError {
    case offline
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case decodingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No internet connection. Records will sync later."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))."
        case .decodingFailed:
            return "Failed to decode server response."
        case .encodingFailed:
            return "Failed to encode request body."
        }
    }
}
