//
//  DepartmentStore.swift
//  ConsTrakr
//

import Foundation

enum DepartmentStore {
    static let catalogDidChangeNotification = Notification.Name("constrakr.departmentsDidChange")

    private static var cachedCatalog: [DepartmentCatalogCategory]?
    private static var cachedCatalogData: Data?

    static var catalog: [DepartmentCatalogCategory] {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.departmentCatalogJSON) else {
            cachedCatalog = DepartmentDefaults.builtInCatalog
            cachedCatalogData = nil
            return DepartmentDefaults.builtInCatalog
        }
        if let cachedCatalog, cachedCatalogData == data {
            return cachedCatalog
        }
        guard
            let decoded = try? JSONDecoder().decode([DepartmentCatalogCategory].self, from: data),
            !decoded.isEmpty
        else {
            cachedCatalog = DepartmentDefaults.builtInCatalog
            cachedCatalogData = data
            return DepartmentDefaults.builtInCatalog
        }
        cachedCatalog = decoded
        cachedCatalogData = data
        return decoded
    }

    static var departmentNames: [String] {
        catalog.map(\.name)
    }

    static func positions(for department: String) -> [String] {
        let normalized = normalize(department)
        guard let match = catalog.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return []
        }
        return match.positions.map(\.name)
    }

    static func applyRemoteCatalog(_ response: DepartmentsResponse) {
        let remote = response.catalog
        guard !remote.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(remote) else { return }
        let existing = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.departmentCatalogJSON)
        if existing == data { return }
        UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.departmentCatalogJSON)
        cachedCatalog = remote
        cachedCatalogData = data
        postChange()
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func isKnownDepartment(_ value: String) -> Bool {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return false }
        return catalog.contains { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    static func isKnownPosition(_ department: String, position: String) -> Bool {
        let pos = normalize(position)
        guard !pos.isEmpty else { return false }
        return positions(for: department).contains { $0.caseInsensitiveCompare(pos) == .orderedSame }
    }

    private static func postChange() {
        NotificationCenter.default.post(name: catalogDidChangeNotification, object: nil)
    }
}
