//
//  APIDecoding.swift
//  ConsTrakr
//
//  Flexible JSON decoding for IMS `/constrakr-api` responses.
//

import Foundation

enum APIDecoding {
    /// Decodes IMS list payloads whether they are a bare array or wrapped (`employees`, `face_embeddings`, etc.).
    static func decodeFlexibleList<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        arrayKeys: [String]
    ) throws -> [T] {
        let decoder = JSONDecoder.api

        if let direct = try? decoder.decode([T].self, from: data) {
            return direct
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw NetworkError.decodingFailed(message: describeDecodingFailure(data: data, underlying: nil))
        }

        if let rows = root as? [[String: Any]] {
            return decodeElements(type, rows: rows, decoder: decoder)
        }

        if let object = root as? [String: Any] {
            for key in arrayKeys {
                if let rows = object[key] as? [[String: Any]] {
                    return decodeElements(type, rows: rows, decoder: decoder)
                }
            }
            return []
        }

        return []
    }

    static func decodeEmployees(from data: Data) -> EmployeeListDecodeResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return EmployeeListDecodeResult(employees: [], rawCount: 0)
        }

        var rows: [[String: Any]] = []
        if let array = root as? [[String: Any]] {
            rows = array
        } else if let object = root as? [String: Any] {
            for key in ["employees", "data", "results"] {
                if let array = object[key] as? [[String: Any]] {
                    rows = array
                    break
                }
            }
        }

        let employees = rows.compactMap { decodeEmployee(dict: $0) }
        return EmployeeListDecodeResult(employees: employees, rawCount: rows.count)
    }

    struct EmployeeListDecodeResult {
        let employees: [EmployeeDTO]
        let rawCount: Int
        var decodedCount: Int { employees.count }
        var skippedCount: Int { max(0, rawCount - decodedCount) }
    }

    static func decodeEmployee(dict: [String: Any]) -> EmployeeDTO? {
        guard let localId = uuidValue(from: dict, key: "local_id") else {
            return nil
        }
        guard let code = stringValue(from: dict, keys: ["employee_code"]), !code.isEmpty else {
            return nil
        }

        return EmployeeDTO(
            serverId: stringValue(from: dict, keys: ["server_id", "id"]),
            localId: localId,
            employeeCode: code,
            firstName: stringValue(from: dict, keys: ["first_name"]) ?? "",
            lastName: stringValue(from: dict, keys: ["last_name"]) ?? "",
            department: stringValue(from: dict, keys: ["department"]) ?? "General",
            assignedSiteId: uuidValue(from: dict, key: "assigned_site_id"),
            assignedSiteName: stringValue(from: dict, keys: ["assigned_site_name"]),
            assignedSiteLocation: stringValue(from: dict, keys: ["assigned_site_location"]),
            encryptedDepthSignatureBase64: stringValue(
                from: dict,
                keys: ["encrypted_depth_signature_base64", "encrypted_depth_signature"]
            ),
            updatedAt: parseISO8601(stringValue(from: dict, keys: ["updated_at"])),
            createdAt: parseISO8601(stringValue(from: dict, keys: ["created_at"]))
        )
    }

    static func normalizeEmployeeCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func decodeUpsertResponse(
        from data: Data,
        expectedLocalId: UUID
    ) throws -> (serverId: String, localId: UUID) {
        if let parsed = parseUpsertPayload(data, expectedLocalId: expectedLocalId) {
            return (parsed.serverId, parsed.localId)
        }

        throw NetworkError.decodingFailed(
            message: describeDecodingFailure(data: data, underlying: nil)
        )
    }

    static func decodeEmployeeUpsert(from data: Data, expectedLocalId: UUID) throws -> EmployeeUpsertResponse {
        if let parsed = parseUpsertPayload(data, expectedLocalId: expectedLocalId) {
            return parsed
        }

        let snippet = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240)
        throw NetworkError.serverError(
            statusCode: 0,
            message: "Employee upload response invalid: \(snippet.map(String.init) ?? "empty body")"
        )
    }

    static func parseUpsertPayload(_ data: Data, expectedLocalId: UUID) -> EmployeeUpsertResponse? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let parsed = parseUpsertObject(object, expectedLocalId: expectedLocalId) {
            return parsed
        }

        let decoder = JSONDecoder.api
        if let direct = try? decoder.decode(EmployeeUpsertResponse.self, from: data),
           normalizedServerId(direct.serverId) != nil {
            return direct
        }

        struct LooseKeys: Decodable {
            let serverId: String?
            let id: String?
            let localId: UUID?

            enum CodingKeys: String, CodingKey {
                case serverId = "server_id"
                case id
                case localId = "local_id"
            }
        }

        if let loose = try? decoder.decode(LooseKeys.self, from: data),
           let serverId = normalizedServerId(loose.serverId ?? loose.id) {
            return EmployeeUpsertResponse(
                serverId: serverId,
                localId: loose.localId ?? expectedLocalId
            )
        }

        if let dto = try? decoder.decode(EmployeeDTO.self, from: data),
           let serverId = normalizedServerId(dto.serverId) {
            return EmployeeUpsertResponse(serverId: serverId, localId: dto.localId)
        }

        return nil
    }

    static func describeDecodingFailure(data: Data, underlying: Error?) -> String {
        let snippet = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240)
        if let underlying {
            return "\(underlying.localizedDescription)\(snippet.map { " — \($0)" } ?? "")"
        }
        return "Unexpected server JSON\(snippet.map { ": \($0)" } ?? ".")"
    }

    private static func parseUpsertObject(
        _ object: [String: Any],
        expectedLocalId: UUID
    ) -> EmployeeUpsertResponse? {
        for nestedKey in ["employee", "data", "result"] {
            if let nested = object[nestedKey] as? [String: Any],
               let parsed = parseUpsertObject(nested, expectedLocalId: expectedLocalId) {
                return parsed
            }
        }

        guard let serverId = normalizedServerId(
            stringValue(from: object, keys: ["server_id", "id", "employee_id", "pk"])
        ) else {
            return nil
        }

        let localId = uuidValue(from: object, key: "local_id") ?? expectedLocalId
        return EmployeeUpsertResponse(serverId: serverId, localId: localId)
    }

    private static func stringValue(from object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let value = object[key] as? Int {
                return String(value)
            } else if let value = object[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func uuidValue(from object: [String: Any], key: String) -> UUID? {
        guard let raw = stringValue(from: object, keys: [key]) else { return nil }
        return UUID(uuidString: raw)
    }

    private static func decodeElements<T: Decodable>(
        _ type: T.Type,
        rows: [[String: Any]],
        decoder: JSONDecoder
    ) -> [T] {
        var decoded: [T] = []
        decoded.reserveCapacity(rows.count)
        for row in rows {
            guard JSONSerialization.isValidJSONObject(row),
                  let rowData = try? JSONSerialization.data(withJSONObject: row),
                  let item = try? decoder.decode(T.self, from: rowData) else {
                continue
            }
            decoded.append(item)
        }
        return decoded
    }

    static func normalizedServerId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parses IMS/Django timestamps (`…Z`, `…+00:00`, fractional seconds).
    static func parseISO8601(_ value: String?) -> Date? {
        guard var string = value?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        string = string.replacingOccurrences(of: "+00:00", with: "Z")

        let formatters: [ISO8601DateFormatter] = {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [fractional, plain]
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    /// Parses `{ "access_token": "...", "expires_in": 86400 }` from IMS login.
    static func parseLoginResponse(from data: Data) -> AdminLoginResponse? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let token = stringValue(from: object, keys: ["access_token", "token"])
        guard let token, !token.isEmpty else { return nil }
        let expiresIn: Int?
        if let value = object["expires_in"] as? Int {
            expiresIn = value
        } else if let value = object["expires_in"] as? Double {
            expiresIn = Int(value)
        } else if let text = object["expires_in"] as? String {
            expiresIn = Int(text)
        } else {
            expiresIn = nil
        }
        return AdminLoginResponse(accessToken: token, expiresIn: expiresIn)
    }

    /// Reads `{ "error": "..." }` from IMS API JSON bodies.
    static func apiErrorMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String else {
            return nil
        }
        return loginErrorMessage(code: error)
    }

    static func loginErrorMessage(code: String) -> String {
        switch code {
        case "invalid_credentials":
            return "Wrong sync admin username or password. Use sync_admin (not the IMS web login). Create it on the server with: python manage.py create_constrakr_admin sync_admin 'your-password'"
        case "username_and_password_required":
            return "Username and password are required."
        default:
            return code.replacingOccurrences(of: "_", with: " ")
        }
    }
}
