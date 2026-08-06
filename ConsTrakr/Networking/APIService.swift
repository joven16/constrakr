//
//  APIService.swift
//  ConsTrakr
//
//  HTTPS client for IMS `/constrakr-api` sync + restore.
//

import Foundation

actor APIService {
    static let shared = APIService()

    private let session: URLSession
    private var baseURLString: String
    private var authToken: String?

    init(session: URLSession = APIService.makeSyncSession(), baseURL: String = AppConstants.apiBaseURL) {
        self.session = session
        let stored = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiBaseURL) ?? baseURL
        self.baseURLString = Self.ensuringHTTPS(stored)
        self.authToken = SyncAuthStore.loadToken()
    }

    func updateBaseURL(_ url: String) {
        baseURLString = Self.ensuringHTTPS(url)
        UserDefaults.standard.set(baseURLString, forKey: AppConstants.UserDefaultsKeys.apiBaseURL)
    }

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    /// Host root for display / tests.
    func currentHostRoot() -> String {
        normalizedHostRoot()
    }

    func isUsingPlaceholderHost() -> Bool {
        isPlaceholderHost
    }

    func hasAuthToken() -> Bool {
        authToken != nil
    }

    // MARK: - Auth

    func adminLogin(username: String, password: String) async throws -> AdminLoginResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .adminLogin)
        request.httpBody = try JSONEncoder.api.encode(AdminLoginRequest(username: username, password: password))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            guard !username.isEmpty, !password.isEmpty else {
                throw NetworkError.serverError(statusCode: 401, message: "Invalid admin credentials.")
            }
            let token = "demo-admin-token-\(UUID().uuidString)"
            authToken = token
            SyncAuthStore.saveSession(token: token, username: username)
            return AdminLoginResponse(accessToken: token, expiresIn: 86400)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        do {
            let decoded = try JSONDecoder.api.decode(AdminLoginResponse.self, from: data)
            authToken = decoded.accessToken
            SyncAuthStore.saveSession(token: decoded.accessToken, username: username)
            return decoded
        } catch {
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240)
            throw NetworkError.serverError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Login response invalid: \(snippet.map(String.init) ?? "decode error")"
            )
        }
    }

    /// Confirms the saved JWT still works (used when Test API runs after sign-in).
    func verifyAuthSession() async throws {
        try rejectIfUnconfigured()
        _ = try await getEmployees()
    }

    func healthCheck() async throws -> Bool {
        try rejectIfUnconfigured()
        if isDemoHost { return true }
        let request = try makeRequest(for: .healthCheck)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return true
    }

    // MARK: - Employees

    func getEmployees() async throws -> [EmployeeDTO] {
        try rejectIfUnconfigured()
        let request = try makeRequest(for: .getEmployees)
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try Self.decodeEmployeeList(from: data)
    }

    func postEmployee(_ dto: EmployeeDTO) async throws -> EmployeeUpsertResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postEmployee)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return EmployeeUpsertResponse(serverId: "srv-emp-\(dto.localId.uuidString)", localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try APIDecoding.decodeEmployeeUpsert(from: data, expectedLocalId: dto.localId)
    }

    func putEmployee(_ dto: EmployeeDTO) async throws -> EmployeeUpsertResponse {
        try rejectIfUnconfigured()
        guard let serverId = dto.serverId else {
            throw NetworkError.invalidURL
        }
        var request = try makeRequest(for: .putEmployee(serverId))
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return EmployeeUpsertResponse(serverId: serverId, localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try APIDecoding.decodeEmployeeUpsert(from: data, expectedLocalId: dto.localId)
    }

    // MARK: - Face embeddings

    func getFaceEmbeddings(employeeServerId: String? = nil) async throws -> [FaceEmbeddingDTO] {
        try rejectIfUnconfigured()
        let request = try makeRequest(for: .getFaceEmbeddings(employeeServerId: employeeServerId))
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode([FaceEmbeddingDTO].self, from: data)
    }

    func postFaceEmbedding(_ dto: FaceEmbeddingDTO) async throws -> FaceEmbeddingUpsertResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postFaceEmbedding)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return FaceEmbeddingUpsertResponse(serverId: "srv-emb-\(dto.localId.uuidString)", localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode(FaceEmbeddingUpsertResponse.self, from: data)
    }

    // MARK: - Enrollment photos

    func getFaceEnrollmentPhotos(employeeServerId: String? = nil) async throws -> [FaceEnrollmentPhotoDTO] {
        try rejectIfUnconfigured()
        let request = try makeRequest(for: .getFaceEnrollmentPhotos(employeeServerId: employeeServerId))
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode([FaceEnrollmentPhotoDTO].self, from: data)
    }

    func postFaceEnrollmentPhoto(_ dto: FaceEnrollmentPhotoDTO) async throws -> FaceEnrollmentPhotoUpsertResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postFaceEnrollmentPhoto)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return FaceEnrollmentPhotoUpsertResponse(
                serverId: "srv-photo-\(dto.localId.uuidString)",
                localId: dto.localId
            )
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode(FaceEnrollmentPhotoUpsertResponse.self, from: data)
    }

    // MARK: - Attendance

    func getAttendance(
        employeeServerId: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> [AttendanceDTO] {
        try rejectIfUnconfigured()
        let request = try makeRequest(
            for: .getAttendance(
                employeeServerId: employeeServerId,
                startDate: startDate,
                endDate: endDate
            )
        )
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode([AttendanceDTO].self, from: data)
    }

    func postAttendance(_ dto: AttendanceDTO) async throws -> AttendanceUpsertResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postAttendance)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return AttendanceUpsertResponse(serverId: "srv-att-\(dto.localId.uuidString)", localId: dto.localId)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode(AttendanceUpsertResponse.self, from: data)
    }

    // MARK: - Helpers

    private static func makeSyncSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    /// Lightweight ping to wake cold hosts (e.g. Render) before bulk sync.
    func warmConnection() async {
        guard !isPlaceholderHost else { return }
        _ = try? await healthCheck()
    }

    private var isDemoHost: Bool {
        normalizedHostRoot().contains("example.com")
    }

    private var isUnconfiguredHost: Bool {
        normalizedHostRoot().contains("your-ims-domain.com")
    }

    private var isPlaceholderHost: Bool {
        isDemoHost || isUnconfiguredHost
    }

    private func rejectIfUnconfigured() throws {
        if isUnconfiguredHost {
            throw NetworkError.serverError(
                statusCode: 0,
                message: "Set your real IMS API URL in Settings (currently your-ims-domain.com)."
            )
        }
    }

    /// Exposed for connection test UI.
    static func previewNormalizedHostRoot(_ baseURL: String) -> String {
        var base = ensuringHTTPS(baseURL)
        let suffix = AppConstants.apiPathPrefix
        if base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    private static func ensuringHTTPS(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        if !value.hasPrefix("https://") {
            value = "https://" + value
        }
        return value
    }

    /// Accepts either `https://host` or `https://host/constrakr-api`.
    private func normalizedHostRoot() -> String {
        var base = baseURLString
        let suffix = AppConstants.apiPathPrefix
        if base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    private static func decodeEmployeeList(from data: Data) throws -> [EmployeeDTO] {
        let decoder = JSONDecoder.api
        if let direct = try? decoder.decode([EmployeeDTO].self, from: data) {
            return direct
        }

        struct Wrapped: Decodable {
            let employees: [EmployeeDTO]?
            let data: [EmployeeDTO]?
            let results: [EmployeeDTO]?
        }

        let wrapped = try decoder.decode(Wrapped.self, from: data)
        if let employees = wrapped.employees { return employees }
        if let data = wrapped.data { return data }
        if let results = wrapped.results { return results }
        return []
    }

    private func makeRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        guard var components = URLComponents(string: normalizedHostRoot() + endpoint.path) else {
            throw NetworkError.invalidURL
        }
        let query = endpoint.queryItems
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        // Render cold starts can exceed 45s on first request after idle.
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.requiresAuth, let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else if endpoint.requiresAuth {
            throw NetworkError.unauthorized
        }
        return request
    }

    private func validate(data: Data?, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        if http.statusCode == 401 {
            authToken = nil
            SyncAuthStore.clear()
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240)
            let detail = snippet.map { String($0) }
            throw NetworkError.serverError(statusCode: http.statusCode, message: detail)
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
