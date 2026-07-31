//
//  APIService.swift
//  ConsTrac
//
//  CHANGE: Placeholder URLSession async/await client for the required endpoints.
//  HTTPS is enforced; example.com host simulates success for offline demos.
//

import Foundation

actor APIService {
    static let shared = APIService()

    private let session: URLSession
    private var baseURLString: String
    /// INTEGRATION: Set from AdminSession after real login.
    private var authToken: String?

    init(session: URLSession = .shared, baseURL: String = AppConstants.apiBaseURL) {
        self.session = session
        let stored = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiBaseURL) ?? baseURL
        self.baseURLString = Self.ensuringHTTPS(stored)
    }

    func updateBaseURL(_ url: String) {
        baseURLString = Self.ensuringHTTPS(url)
        UserDefaults.standard.set(baseURLString, forKey: AppConstants.UserDefaultsKeys.apiBaseURL)
    }

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    // MARK: - Auth

    /// PLACEHOLDER: Admin login for restore-on-new-device.
    func adminLogin(username: String, password: String) async throws -> AdminLoginResponse {
        var request = try makeRequest(for: .adminLogin)
        request.httpBody = try JSONEncoder.api.encode(AdminLoginRequest(username: username, password: password))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isPlaceholderHost {
            // Demo credentials for local development without a backend.
            guard !username.isEmpty, !password.isEmpty else {
                throw NetworkError.serverError(statusCode: 401, message: "Invalid admin credentials.")
            }
            let token = "demo-admin-token-\(UUID().uuidString)"
            authToken = token
            return AdminLoginResponse(accessToken: token, expiresIn: 3600)
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)
        let decoded = try JSONDecoder.api.decode(AdminLoginResponse.self, from: data)
        authToken = decoded.accessToken
        return decoded
    }

    func healthCheck() async throws -> Bool {
        let request = try makeRequest(for: .healthCheck)
        if isPlaceholderHost { return true }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        return (200..<300).contains(http.statusCode)
    }

    // MARK: - Employees  GET/POST /employees

    func getEmployees() async throws -> [EmployeeDTO] {
        let request = try makeRequest(for: .getEmployees)
        if isPlaceholderHost {
            // PLACEHOLDER restore payload — empty unless you seed a demo catalog.
            return []
        }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder.api.decode([EmployeeDTO].self, from: data)
    }

    func postEmployee(_ dto: EmployeeDTO) async throws -> EmployeeUpsertResponse {
        var request = try makeRequest(for: .postEmployee)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isPlaceholderHost {
            return EmployeeUpsertResponse(serverId: "srv-emp-\(dto.localId.uuidString)", localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder.api.decode(EmployeeUpsertResponse.self, from: data)
    }

    // MARK: - Face embeddings  GET/POST /face-embeddings

    func getFaceEmbeddings() async throws -> [FaceEmbeddingDTO] {
        let request = try makeRequest(for: .getFaceEmbeddings)
        if isPlaceholderHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder.api.decode([FaceEmbeddingDTO].self, from: data)
    }

    func postFaceEmbedding(_ dto: FaceEmbeddingDTO) async throws -> FaceEmbeddingUpsertResponse {
        var request = try makeRequest(for: .postFaceEmbedding)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isPlaceholderHost {
            return FaceEmbeddingUpsertResponse(serverId: "srv-emb-\(dto.localId.uuidString)", localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder.api.decode(FaceEmbeddingUpsertResponse.self, from: data)
    }

    // MARK: - Attendance  GET/POST /attendance

    func getAttendance() async throws -> [AttendanceDTO] {
        let request = try makeRequest(for: .getAttendance)
        if isPlaceholderHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder.api.decode([AttendanceDTO].self, from: data)
    }

    func postAttendance(_ dto: AttendanceDTO) async throws -> AttendanceUpsertResponse {
        var request = try makeRequest(for: .postAttendance)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isPlaceholderHost {
            return AttendanceUpsertResponse(serverId: "srv-att-\(dto.localId.uuidString)", localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder.api.decode(AttendanceUpsertResponse.self, from: data)
    }

    // MARK: - Helpers

    private var isPlaceholderHost: Bool {
        baseURLString.contains("example.com")
    }

    private static func ensuringHTTPS(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        if !value.hasPrefix("https://") {
            value = "https://" + value
        }
        return value
    }

    private func makeRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        guard let url = URL(string: baseURLString + endpoint.path) else {
            throw NetworkError.invalidURL
        }
        // Security: only HTTPS URLs are constructed after ensuringHTTPS(_:).
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.serverError(statusCode: http.statusCode, message: nil)
        }
    }
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
