//
//  APIEndpoints.swift
//  ConsTrakr
//
//  CHANGE: Placeholder REST surface aligned to offline-first sync + restore.
//  INTEGRATION: Point base URL at your real HTTPS backend when ready.
//

import Foundation

enum APIEndpoint {
    // Employees
    case getEmployees
    case postEmployee
    case putEmployee(String)
    case deleteEmployee(String)
    // Face embeddings (encrypted payloads only)
    case getFaceEmbeddings(employeeServerId: String?)
    case postFaceEmbedding
    // Enrollment face JPEGs (one row per pose)
    case getFaceEnrollmentPhotos(employeeServerId: String?, includeMedia: Bool)
    case postFaceEnrollmentPhoto
    // Attendance
    case getAttendance(employeeServerId: String?, startDate: Date?, endDate: Date?, includeMedia: Bool)
    case postAttendance
    // Job sites
    case getJobSites
    case postJobSite
    case putJobSite(String)
    case deleteJobSite(String)
    // Auth / health (restore gate)
    case adminLogin
    case healthCheck

    private static var root: String { AppConstants.apiPathPrefix }

    var path: String {
        switch self {
        case .getEmployees, .postEmployee:
            return "\(Self.root)/employees"
        case .putEmployee(let serverId), .deleteEmployee(let serverId):
            return "\(Self.root)/employees/\(serverId)"
        case .getFaceEmbeddings, .postFaceEmbedding:
            return "\(Self.root)/face-embeddings"
        case .getFaceEnrollmentPhotos, .postFaceEnrollmentPhoto:
            return "\(Self.root)/face-enrollment-photos"
        case .getAttendance, .postAttendance:
            return "\(Self.root)/attendance"
        case .getJobSites, .postJobSite:
            return "\(Self.root)/job-sites"
        case .putJobSite(let siteId), .deleteJobSite(let siteId):
            return "\(Self.root)/job-sites/\(siteId)"
        case .adminLogin:
            return "\(Self.root)/auth/admin/login"
        case .healthCheck:
            return "\(Self.root)/health"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .getFaceEmbeddings(let employeeServerId):
            guard let employeeServerId else { return [] }
            return [URLQueryItem(name: "employee_server_id", value: employeeServerId)]
        case .getFaceEnrollmentPhotos(let employeeServerId, let includeMedia):
            var items: [URLQueryItem] = []
            if let employeeServerId {
                items.append(URLQueryItem(name: "employee_server_id", value: employeeServerId))
            }
            if includeMedia {
                items.append(URLQueryItem(name: "include_media", value: "1"))
            }
            return items
        case .getAttendance(let employeeServerId, let startDate, let endDate, let includeMedia):
            var items: [URLQueryItem] = []
            if let employeeServerId {
                items.append(URLQueryItem(name: "employee_server_id", value: employeeServerId))
            }
            if let startDate {
                items.append(URLQueryItem(name: "start_date", value: Self.dateQueryString(startDate)))
            }
            if let endDate {
                items.append(URLQueryItem(name: "end_date", value: Self.dateQueryString(endDate)))
            }
            if includeMedia {
                items.append(URLQueryItem(name: "include_media", value: "1"))
            }
            return items
        default:
            return []
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .adminLogin, .healthCheck:
            return false
        default:
            return true
        }
    }

    private static func dateQueryString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    var method: String {
        switch self {
        case .postEmployee, .postFaceEmbedding, .postFaceEnrollmentPhoto, .postAttendance, .postJobSite, .adminLogin:
            return "POST"
        case .putEmployee, .putJobSite:
            return "PUT"
        case .deleteEmployee, .deleteJobSite:
            return "DELETE"
        case .getEmployees, .getFaceEmbeddings, .getFaceEnrollmentPhotos, .getAttendance, .getJobSites, .healthCheck:
            return "GET"
        }
    }
}

// MARK: - DTOs (local id vs server id kept explicit)

struct EmployeeDTO: Codable, Identifiable {
    /// Backend employee id when known; for POST responses.
    let serverId: String?
    /// Client local UUID — backend should store for idempotent upserts.
    let localId: UUID
    let employeeCode: String
    let firstName: String
    let lastName: String
    let department: String
    let assignedSiteId: UUID?
    let assignedSiteName: String?
    let assignedSiteLocation: String?
    /// AES-GCM encrypted TrueDepth signature (empty when device has no TrueDepth).
    let encryptedDepthSignatureBase64: String?
    let updatedAt: Date?
    let createdAt: Date?

    var id: UUID { localId }

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
        case employeeCode = "employee_code"
        case firstName = "first_name"
        case lastName = "last_name"
        case department
        case assignedSiteId = "assigned_site_id"
        case assignedSiteName = "assigned_site_name"
        case assignedSiteLocation = "assigned_site_location"
        case encryptedDepthSignatureBase64 = "encrypted_depth_signature_base64"
        case encryptedDepthSignature = "encrypted_depth_signature"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    init(
        serverId: String?,
        localId: UUID,
        employeeCode: String,
        firstName: String,
        lastName: String,
        department: String,
        assignedSiteId: UUID? = nil,
        assignedSiteName: String? = nil,
        assignedSiteLocation: String? = nil,
        encryptedDepthSignatureBase64: String? = nil,
        updatedAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.serverId = serverId
        self.localId = localId
        self.employeeCode = employeeCode
        self.firstName = firstName
        self.lastName = lastName
        self.department = department
        self.assignedSiteId = assignedSiteId
        self.assignedSiteName = assignedSiteName
        self.assignedSiteLocation = assignedSiteLocation
        self.encryptedDepthSignatureBase64 = encryptedDepthSignatureBase64
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    /// Builds sync payload including denormalized job site labels for IMS display.
    static func fromLocalEmployee(_ employee: Employee, serverId: String?) -> EmployeeDTO {
        let site = JobSiteStore.syncFields(for: employee.assignedSiteId)
        return EmployeeDTO(
            serverId: serverId,
            localId: employee.id,
            employeeCode: employee.employeeCode,
            firstName: employee.firstName,
            lastName: employee.lastName,
            department: employee.department,
            assignedSiteId: site.id,
            assignedSiteName: site.name,
            assignedSiteLocation: site.location,
            encryptedDepthSignatureBase64: employee.faceDepthSignatureData.isEmpty
                ? nil
                : employee.faceDepthSignatureData.base64EncodedString(),
            updatedAt: employee.updatedAt,
            createdAt: employee.createdAt
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        localId = try container.decode(UUID.self, forKey: .localId)
        employeeCode = try container.decode(String.self, forKey: .employeeCode)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        department = try container.decodeIfPresent(String.self, forKey: .department) ?? "General"
        assignedSiteId = try container.decodeIfPresent(UUID.self, forKey: .assignedSiteId)
        assignedSiteName = try container.decodeIfPresent(String.self, forKey: .assignedSiteName)
        assignedSiteLocation = try container.decodeIfPresent(String.self, forKey: .assignedSiteLocation)
        encryptedDepthSignatureBase64 = try container.decodeIfPresent(
            String.self,
            forKey: .encryptedDepthSignatureBase64
        ) ?? container.decodeIfPresent(String.self, forKey: .encryptedDepthSignature)
        updatedAt = Self.decodeOptionalDate(from: container, forKey: .updatedAt)
        createdAt = Self.decodeOptionalDate(from: container, forKey: .createdAt)
    }

    private static func decodeOptionalDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return APIDecoding.parseISO8601(string)
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(serverId, forKey: .serverId)
        try container.encode(localId, forKey: .localId)
        try container.encode(employeeCode, forKey: .employeeCode)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(department, forKey: .department)
        try container.encodeIfPresent(assignedSiteId, forKey: .assignedSiteId)
        try container.encodeIfPresent(assignedSiteName, forKey: .assignedSiteName)
        try container.encodeIfPresent(assignedSiteLocation, forKey: .assignedSiteLocation)
        try container.encodeIfPresent(encryptedDepthSignatureBase64, forKey: .encryptedDepthSignatureBase64)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct JobSiteDTO: Codable, Identifiable {
    let id: UUID
    let name: String
    let locationLabel: String?
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case locationLabel = "location_label"
        case latitude
        case longitude
        case radiusMeters = "radius_meters"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        name: String,
        locationLabel: String? = nil,
        latitude: Double = 0,
        longitude: Double = 0,
        radiusMeters: Double = 150,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.locationLabel = locationLabel
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    static func fromLocal(_ site: JobSite) -> JobSiteDTO {
        let location = site.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return JobSiteDTO(
            id: site.id,
            name: site.displayTitle,
            locationLabel: location.isEmpty ? nil : location,
            latitude: site.latitude,
            longitude: site.longitude,
            radiusMeters: site.radiusMeters,
            updatedAt: site.updatedAt
        )
    }

    func toJobSite() -> JobSite {
        JobSite(
            id: id,
            name: name,
            locationLabel: locationLabel ?? "",
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            updatedAt: updatedAt ?? .distantPast
        )
    }
}

struct EmployeeUpsertResponse: Decodable {
    let serverId: String
    let localId: UUID

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
    }

    init(serverId: String, localId: UUID) {
        self.serverId = serverId
        self.localId = localId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .serverId) {
            serverId = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            serverId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.serverId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing server_id or id")
            )
        }
        localId = try container.decode(UUID.self, forKey: .localId)
    }
}

struct FaceEmbeddingDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let pose: String
    /// Base64 of AES-GCM ciphertext — never plaintext floats over the wire.
    let encryptedValuesBase64: String

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
        case employeeServerId = "employee_server_id"
        case employeeLocalId = "employee_local_id"
        case pose
        case encryptedValuesBase64 = "encrypted_values_base64"
        case encryptedValues = "encrypted_values"
    }

    init(
        serverId: String?,
        localId: UUID,
        employeeServerId: String?,
        employeeLocalId: UUID,
        pose: String,
        encryptedValuesBase64: String
    ) {
        self.serverId = serverId
        self.localId = localId
        self.employeeServerId = employeeServerId
        self.employeeLocalId = employeeLocalId
        self.pose = pose
        self.encryptedValuesBase64 = encryptedValuesBase64
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        localId = try container.decode(UUID.self, forKey: .localId)
        employeeServerId = try container.decodeIfPresent(String.self, forKey: .employeeServerId)
        employeeLocalId = try container.decode(UUID.self, forKey: .employeeLocalId)
        pose = try container.decode(String.self, forKey: .pose)
        encryptedValuesBase64 = try container.decodeIfPresent(String.self, forKey: .encryptedValuesBase64)
            ?? container.decodeIfPresent(String.self, forKey: .encryptedValues)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(serverId, forKey: .serverId)
        try container.encode(localId, forKey: .localId)
        try container.encodeIfPresent(employeeServerId, forKey: .employeeServerId)
        try container.encode(employeeLocalId, forKey: .employeeLocalId)
        try container.encode(pose, forKey: .pose)
        try container.encode(encryptedValuesBase64, forKey: .encryptedValuesBase64)
    }
}

struct FaceEmbeddingUpsertResponse: Decodable {
    let serverId: String
    let localId: UUID

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
    }

    init(serverId: String, localId: UUID) {
        self.serverId = serverId
        self.localId = localId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .serverId) {
            serverId = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            serverId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.serverId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing server_id or id")
            )
        }
        localId = try container.decode(UUID.self, forKey: .localId)
    }
}

struct FaceEnrollmentPhotoDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let pose: String
    /// JPEG bytes, base64 — required for POST; optional on GET list responses.
    let jpegBase64: String?
    let hasJpegData: Bool?

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
        case employeeServerId = "employee_server_id"
        case employeeLocalId = "employee_local_id"
        case pose
        case jpegBase64 = "jpeg_base64"
        case hasJpegData = "has_jpeg_data"
    }

    init(
        serverId: String?,
        localId: UUID,
        employeeServerId: String?,
        employeeLocalId: UUID,
        pose: String,
        jpegBase64: String?,
        hasJpegData: Bool? = nil
    ) {
        self.serverId = serverId
        self.localId = localId
        self.employeeServerId = employeeServerId
        self.employeeLocalId = employeeLocalId
        self.pose = pose
        self.jpegBase64 = jpegBase64
        self.hasJpegData = hasJpegData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        localId = try container.decode(UUID.self, forKey: .localId)
        employeeServerId = try container.decodeIfPresent(String.self, forKey: .employeeServerId)
        employeeLocalId = try container.decode(UUID.self, forKey: .employeeLocalId)
        pose = try container.decode(String.self, forKey: .pose)
        jpegBase64 = try container.decodeIfPresent(String.self, forKey: .jpegBase64)
        hasJpegData = try container.decodeIfPresent(Bool.self, forKey: .hasJpegData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(serverId, forKey: .serverId)
        try container.encode(localId, forKey: .localId)
        try container.encodeIfPresent(employeeServerId, forKey: .employeeServerId)
        try container.encode(employeeLocalId, forKey: .employeeLocalId)
        try container.encode(pose, forKey: .pose)
        try container.encodeIfPresent(jpegBase64, forKey: .jpegBase64)
    }
}

struct FaceEnrollmentPhotoUpsertResponse: Decodable {
    let serverId: String
    let localId: UUID

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
    }

    init(serverId: String, localId: UUID) {
        self.serverId = serverId
        self.localId = localId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .serverId) {
            serverId = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            serverId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.serverId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing server_id or id")
            )
        }
        localId = try container.decode(UUID.self, forKey: .localId)
    }
}

struct AttendanceDTO: Codable {
    let serverId: String?
    let localId: UUID
    let employeeServerId: String?
    let employeeLocalId: UUID
    let checkType: String
    let timestamp: Date
    let confidenceScore: Double
    let notes: String?
    /// Optional punch-time face crop (JPEG, base64).
    let punchPhotoBase64: String?

    init(
        serverId: String?,
        localId: UUID,
        employeeServerId: String?,
        employeeLocalId: UUID,
        checkType: String,
        timestamp: Date,
        confidenceScore: Double,
        notes: String?,
        punchPhotoBase64: String? = nil
    ) {
        self.serverId = serverId
        self.localId = localId
        self.employeeServerId = employeeServerId
        self.employeeLocalId = employeeLocalId
        self.checkType = checkType
        self.timestamp = timestamp
        self.confidenceScore = confidenceScore
        self.notes = notes
        self.punchPhotoBase64 = punchPhotoBase64
    }
}

struct AttendanceUpsertResponse: Decodable {
    let serverId: String
    let localId: UUID

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case id
        case localId = "local_id"
    }

    init(serverId: String, localId: UUID) {
        self.serverId = serverId
        self.localId = localId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .serverId) {
            serverId = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            serverId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.serverId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing server_id or id")
            )
        }
        localId = try container.decode(UUID.self, forKey: .localId)
    }
}

struct AdminLoginRequest: Codable {
    let username: String
    let password: String
}

struct AdminLoginResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case token
        case expiresIn = "expires_in"
    }

    init(accessToken: String, expiresIn: Int?) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .accessToken) {
            accessToken = token
        } else if let token = try container.decodeIfPresent(String.self, forKey: .token) {
            accessToken = token
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.accessToken,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing access_token or token")
            )
        }
        expiresIn = Self.decodeFlexibleInt(from: container, forKey: .expiresIn)
    }

    private static func decodeFlexibleInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(text)
        }
        return nil
    }
}

/// Legacy batch response shape kept for compatibility with older SyncQueue call sites.
struct AttendanceSyncResponse: Codable {
    let syncedIds: [UUID]
    let failedIds: [UUID]
}
