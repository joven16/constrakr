//
//  DepartmentStore.swift
//  ConsTrakr
//

import Foundation

enum DepartmentStore {
    static let catalogDidChangeNotification = Notification.Name("constrakr.departmentsDidChange")

    static var customDepartments: [String] {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.customDepartmentsJSON),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    static var allOptions: [String] {
        merge(defaults: DepartmentDefaults.builtIn, custom: customDepartments)
    }

    static func applyRemoteCatalog(_ options: [String]) {
        let builtInLower = Set(DepartmentDefaults.builtIn.map { $0.lowercased() })
        let customOnly = options.compactMap { name -> String? in
            let trimmed = normalize(name)
            guard !trimmed.isEmpty else { return nil }
            return builtInLower.contains(trimmed.lowercased()) ? nil : trimmed
        }
        let mergedCustom = merge(defaults: [], custom: customOnly)
        guard mergedCustom != customDepartments else { return }
        if let data = try? JSONEncoder().encode(mergedCustom) {
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.customDepartmentsJSON)
            postChange()
        }
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func isPreset(_ value: String) -> Bool {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return false }
        return allOptions.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    static func displayOptions(including value: String) -> [String] {
        var options = allOptions
        let normalized = normalize(value)
        if !normalized.isEmpty,
           !options.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            options.append(normalized)
        }
        return options
    }

    private static func merge(defaults: [String], custom: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for name in defaults + custom {
            let cleaned = normalize(name)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(cleaned)
        }
        return merged
    }

    private static func postChange() {
        NotificationCenter.default.post(name: catalogDidChangeNotification, object: nil)
    }
}
