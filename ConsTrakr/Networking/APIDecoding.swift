//
//  APIDecoding.swift
//  ConsTrakr
//
//  Flexible JSON decoding for IMS `/constrakr-api` responses.
//

import Foundation

enum APIDecoding {
    static func decodeEmployeeUpsert(from data: Data, expectedLocalId: UUID) throws -> EmployeeUpsertResponse {
        let decoder = JSONDecoder.api

        if let direct = try? decoder.decode(EmployeeUpsertResponse.self, from: data) {
            return direct
        }

        if let dto = try? decoder.decode(EmployeeDTO.self, from: data),
           let serverId = normalizedServerId(dto.serverId) {
            return EmployeeUpsertResponse(serverId: serverId, localId: dto.localId)
        }

        struct WrappedEmployee: Decodable {
            let employee: EmployeeDTO?
            let data: EmployeeDTO?
            let result: EmployeeDTO?
        }

        if let wrapped = try? decoder.decode(WrappedEmployee.self, from: data) {
            for candidate in [wrapped.employee, wrapped.data, wrapped.result].compactMap({ $0 }) {
                if let serverId = normalizedServerId(candidate.serverId) {
                    return EmployeeUpsertResponse(serverId: serverId, localId: candidate.localId)
                }
            }
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

        let snippet = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240)
        throw NetworkError.serverError(
            statusCode: 0,
            message: "Employee upload response invalid: \(snippet.map(String.init) ?? "empty body")"
        )
    }

    static func normalizedServerId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
