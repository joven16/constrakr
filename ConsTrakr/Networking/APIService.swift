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
            SyncAuthStore.saveSession(token: token, username: username, expiresIn: 86400)
            return AdminLoginResponse(accessToken: token, expiresIn: 86400)
        }

        let (data, response) = try await session.data(for: request)
        try validateLogin(data: data, response: response)
        do {
            let decoded = try JSONDecoder.api.decode(AdminLoginResponse.self, from: data)
            guard !decoded.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NetworkError.serverError(statusCode: 200, message: "Login succeeded but access_token was empty.")
            }
            authToken = decoded.accessToken
            SyncAuthStore.saveSession(token: decoded.accessToken, username: username, expiresIn: decoded.expiresIn)
            return decoded
        } catch let error as NetworkError {
            throw error
        } catch {
            if let parsed = APIDecoding.parseLoginResponse(from: data) {
                authToken = parsed.accessToken
                SyncAuthStore.saveSession(token: parsed.accessToken, username: username, expiresIn: parsed.expiresIn)
                return parsed
            }
            if let apiError = APIDecoding.apiErrorMessage(from: data) {
                throw NetworkError.serverError(
                    statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    message: apiError
                )
            }
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240)
            let body = snippet.map(String.init) ?? "decode error"
            let hint = body.lowercased().contains("<!doctype html") || body.lowercased().contains("<html")
                ? " Check Base URL is host only, e.g. https://ims.rentelloph.com (not the web login page)."
                : ""
            throw NetworkError.serverError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Login response invalid (expected access_token JSON): \(body)\(hint)"
            )
        }
    }

    private func validateLogin(data: Data?, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        if http.statusCode == 401 {
            authToken = nil
            SyncAuthStore.clear()
            throw NetworkError.serverError(
                statusCode: 401,
                message: APIDecoding.apiErrorMessage(from: data)
                    ?? "Wrong sync admin username or password."
            )
        }
        try validate(data: data, response: response)
    }

    /// Confirms the saved JWT still works (used when Test API runs after sign-in).
    func verifyAuthSession() async throws {
        try rejectIfUnconfigured()
        _ = try await getEmployees()
    }

    func healthCheck() async throws -> Bool {
        _ = try await fetchServerTime()
        return true
    }

    func fetchServerTime() async throws -> Date {
        try rejectIfUnconfigured()
        if isDemoHost { return Date() }
        let request = try makeRequest(for: .healthCheck)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)

        struct HealthResponse: Decodable {
            let serverTime: Date?

            enum CodingKeys: String, CodingKey {
                case serverTime = "server_time"
            }
        }

        if let decoded = try? JSONDecoder.api.decode(HealthResponse.self, from: data),
           let serverTime = decoded.serverTime {
            return serverTime
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = object["server_time"] as? String,
           let parsed = APIDecoding.parseISO8601(raw) {
            return parsed
        }

        throw NetworkError.decodingFailed(message: "Health response missing server_time")
    }

    // MARK: - Employees

    /// Raw JSON body for lenient employee roster parsing.
    func fetchEmployeesData(
        localId: UUID? = nil,
        employeeCode: String? = nil,
        serverId: String? = nil,
        updatedSince: Date? = nil
    ) async throws -> Data {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .getEmployees)
        if let url = request.url,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var query = components.queryItems ?? []
            if let localId {
                query.append(URLQueryItem(name: "local_id", value: localId.uuidString))
            }
            if let employeeCode, !employeeCode.isEmpty {
                query.append(URLQueryItem(name: "employee_code", value: employeeCode))
            }
            if let serverId, !serverId.isEmpty {
                query.append(URLQueryItem(name: "server_id", value: serverId))
            }
            if let updatedSince {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                query.append(URLQueryItem(name: "updated_since", value: formatter.string(from: updatedSince)))
            }
            if !query.isEmpty {
                components.queryItems = query
                request.url = components.url
            }
        }
        if isDemoHost { return Data("{}".utf8) }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return data
    }

    func getEmployees(
        localId: UUID? = nil,
        employeeCode: String? = nil,
        serverId: String? = nil,
        updatedSince: Date? = nil
    ) async throws -> [EmployeeDTO] {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .getEmployees)
        if let url = request.url,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var query = components.queryItems ?? []
            if let localId {
                query.append(URLQueryItem(name: "local_id", value: localId.uuidString))
            }
            if let employeeCode, !employeeCode.isEmpty {
                query.append(URLQueryItem(name: "employee_code", value: employeeCode))
            }
            if let serverId, !serverId.isEmpty {
                query.append(URLQueryItem(name: "server_id", value: serverId))
            }
            if let updatedSince {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                query.append(URLQueryItem(name: "updated_since", value: formatter.string(from: updatedSince)))
            }
            if !query.isEmpty {
                components.queryItems = query
                request.url = components.url
            }
        }
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        let parsed = APIDecoding.decodeEmployees(from: data)
        if parsed.rawCount > 0, parsed.decodedCount == 0 {
            throw NetworkError.decodingFailed(
                message: "Could not read \(parsed.rawCount) employee(s) from IMS. Tap Sync Now to retry."
            )
        }
        return parsed.employees
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
        if let parsed = APIDecoding.parseUpsertPayload(data, expectedLocalId: dto.localId) {
            return parsed
        }
        if let recovered = try await recoverEmployeeUpsert(localId: dto.localId, employeeCode: dto.employeeCode) {
            return recovered
        }
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
        if let parsed = APIDecoding.parseUpsertPayload(data, expectedLocalId: dto.localId) {
            return parsed
        }
        if let recovered = try await recoverEmployeeUpsert(localId: dto.localId, employeeCode: dto.employeeCode) {
            return recovered
        }
        return try APIDecoding.decodeEmployeeUpsert(from: data, expectedLocalId: dto.localId)
    }

    func deleteEmployee(serverId: String) async throws {
        try rejectIfUnconfigured()
        let normalized = serverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NetworkError.invalidURL
        }
        let request = try makeRequest(for: .deleteEmployee(normalized))
        if isDemoHost { return }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    // MARK: - Job sites

    func getJobSites() async throws -> [JobSiteDTO] {
        try rejectIfUnconfigured()
        let request = try makeRequest(for: .getJobSites)
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try APIDecoding.decodeFlexibleList(
            JobSiteDTO.self,
            from: data,
            arrayKeys: ["job_sites", "sites", "data", "results"]
        )
    }

    func postJobSite(_ dto: JobSiteDTO) async throws -> JobSiteDTO {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postJobSite)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if isDemoHost { return dto }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        if let decoded = try? JSONDecoder.api.decode(JobSiteDTO.self, from: data) {
            return decoded
        }
        return dto
    }

    func putJobSite(_ dto: JobSiteDTO) async throws -> JobSiteDTO {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .putJobSite(dto.id.uuidString))
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if isDemoHost { return dto }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        if let decoded = try? JSONDecoder.api.decode(JobSiteDTO.self, from: data) {
            return decoded
        }
        return dto
    }

    func deleteJobSite(id: UUID) async throws {
        try rejectIfUnconfigured()
        let request = try makeRequest(for: .deleteJobSite(id.uuidString))
        if isDemoHost { return }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    private func recoverEmployeeUpsert(localId: UUID, employeeCode: String) async throws -> EmployeeUpsertResponse? {
        let byLocal = try await getEmployees(localId: localId)
        if let match = byLocal.first,
           let serverId = APIDecoding.normalizedServerId(match.serverId) {
            return EmployeeUpsertResponse(serverId: serverId, localId: match.localId)
        }

        let byCode = try await getEmployees(employeeCode: employeeCode)
        if let match = byCode.first,
           let serverId = APIDecoding.normalizedServerId(match.serverId) {
            return EmployeeUpsertResponse(serverId: serverId, localId: match.localId)
        }

        return nil
    }

    // MARK: - Face embeddings

    func getFaceEmbeddings(employeeServerId: String? = nil) async throws -> [FaceEmbeddingDTO] {
        try rejectIfUnconfigured()
        let request = try makeRequest(for: .getFaceEmbeddings(employeeServerId: employeeServerId))
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        do {
            return try APIDecoding.decodeFlexibleList(
                FaceEmbeddingDTO.self,
                from: data,
                arrayKeys: ["face_embeddings", "embeddings", "data", "results"]
            )
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingFailed(
                message: APIDecoding.describeDecodingFailure(data: data, underlying: error)
            )
        }
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
        let parsed = try APIDecoding.decodeUpsertResponse(from: data, expectedLocalId: dto.localId)
        return FaceEmbeddingUpsertResponse(serverId: parsed.serverId, localId: parsed.localId)
    }

    // MARK: - Enrollment photos

    func getFaceEnrollmentPhotos(
        employeeServerId: String? = nil,
        includeMedia: Bool = false
    ) async throws -> [FaceEnrollmentPhotoDTO] {
        try rejectIfUnconfigured()
        var request = try makeRequest(
            for: .getFaceEnrollmentPhotos(employeeServerId: employeeServerId, includeMedia: includeMedia)
        )
        if includeMedia { request.timeoutInterval = 300 }
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        do {
            return try APIDecoding.decodeFlexibleList(
                FaceEnrollmentPhotoDTO.self,
                from: data,
                arrayKeys: ["face_enrollment_photos", "photos", "data", "results"]
            )
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingFailed(
                message: APIDecoding.describeDecodingFailure(data: data, underlying: error)
            )
        }
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
        let parsed = try APIDecoding.decodeUpsertResponse(from: data, expectedLocalId: dto.localId)
        return FaceEnrollmentPhotoUpsertResponse(serverId: parsed.serverId, localId: parsed.localId)
    }

    // MARK: - Employee ID documents

    func getEmployeeIdDocuments(
        employeeServerId: String? = nil,
        includeMedia: Bool = false
    ) async throws -> [EmployeeIdDocumentDTO] {
        try rejectIfUnconfigured()
        var request = try makeRequest(
            for: .getEmployeeIdDocuments(employeeServerId: employeeServerId, includeMedia: includeMedia)
        )
        if includeMedia { request.timeoutInterval = 300 }
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try APIDecoding.decodeFlexibleList(
            EmployeeIdDocumentDTO.self,
            from: data,
            arrayKeys: ["employee_id_documents", "documents", "data", "results"]
        )
    }

    func postEmployeeIdDocument(_ dto: EmployeeIdDocumentDTO) async throws -> EmployeeIdDocumentUpsertResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postEmployeeIdDocument)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return EmployeeIdDocumentUpsertResponse(
                employeeServerId: dto.employeeServerId ?? "srv-id-\(dto.employeeLocalId.uuidString)",
                employeeLocalId: dto.employeeLocalId
            )
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder.api.decode(EmployeeIdDocumentUpsertResponse.self, from: data)
    }

    // MARK: - Attendance

    func getAttendance(
        employeeServerId: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        includeMedia: Bool = false,
        updatedSince: Date? = nil
    ) async throws -> [AttendanceDTO] {
        try rejectIfUnconfigured()
        var request = try makeRequest(
            for: .getAttendance(
                employeeServerId: employeeServerId,
                startDate: startDate,
                endDate: endDate,
                includeMedia: includeMedia,
                updatedSince: updatedSince
            )
        )
        if includeMedia { request.timeoutInterval = 300 }
        if isDemoHost { return [] }
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        do {
            return try APIDecoding.decodeFlexibleList(
                AttendanceDTO.self,
                from: data,
                arrayKeys: ["attendance", "records", "data", "results"]
            )
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingFailed(
                message: APIDecoding.describeDecodingFailure(data: data, underlying: error)
            )
        }
    }

    func postAttendance(_ dto: AttendanceDTO) async throws -> AttendanceUpsertResponse {
        try rejectIfUnconfigured()
        var request = try makeRequest(for: .postAttendance)
        request.httpBody = try JSONEncoder.api.encode(dto)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isDemoHost {
            return AttendanceUpsertResponse(serverId: "srv-att-\(dto.localId.uuidString)", localId: dto.localId, timestamp: dto.timestamp)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        if let decoded = try? JSONDecoder.api.decode(AttendanceUpsertResponse.self, from: data) {
            return decoded
        }
        let parsed = try APIDecoding.decodeUpsertResponse(from: data, expectedLocalId: dto.localId)
        return AttendanceUpsertResponse(serverId: parsed.serverId, localId: parsed.localId, timestamp: dto.timestamp)
    }

    // MARK: - Helpers

    private static func makeSyncSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
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
        request.timeoutInterval = 90
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
