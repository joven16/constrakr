//
//  DepartmentAndPositionFields.swift
//  ConsTrakr
//

import SwiftUI

struct DepartmentAndPositionFields: View {
    @Binding var department: String
    @Binding var position: String

    private var departments: [DepartmentCatalogCategory] {
        DepartmentStore.catalog
    }

    private var hasDepartment: Bool {
        let normalized = DepartmentStore.normalize(department)
        guard !normalized.isEmpty else { return false }
        return DepartmentStore.isKnownDepartment(normalized) || isLegacyDepartment
    }

    private var isLegacyDepartment: Bool {
        let normalized = DepartmentStore.normalize(department)
        guard !normalized.isEmpty else { return false }
        return !DepartmentStore.isKnownDepartment(normalized)
    }

    private var positionOptions: [String] {
        guard DepartmentStore.isKnownDepartment(department) else { return [] }
        return DepartmentStore.positions(for: department)
    }

    var body: some View {
        Group {
            Picker("Department", selection: $department) {
                Text("Select department").tag("")
                ForEach(departments) { category in
                    Text(category.name).tag(category.name)
                }
                if isLegacyDepartment {
                    Text("\(department) (legacy)").tag(department)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: department) { _, newValue in
                guard DepartmentStore.isKnownDepartment(newValue) else {
                    position = ""
                    return
                }
                let options = DepartmentStore.positions(for: newValue)
                if options.contains(where: { $0.caseInsensitiveCompare(position) == .orderedSame }) {
                    return
                }
                position = ""
            }

            if !hasDepartment {
                LabeledContent("Position") {
                    Text("Select department first")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else if isLegacyDepartment {
                TextField("Position", text: $position)
                    .textInputAutocapitalization(.words)
            } else if positionOptions.isEmpty {
                TextField("Position", text: $position)
                    .textInputAutocapitalization(.words)
            } else {
                Picker("Position", selection: $position) {
                    Text("Select position").tag("")
                    ForEach(positionOptions, id: \.self) { title in
                        Text(title).tag(title)
                    }
                    if !position.isEmpty,
                       !positionOptions.contains(where: { $0.caseInsensitiveCompare(position) == .orderedSame }) {
                        Text("\(position) (legacy)").tag(position)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .onAppear { normalizeExistingValues() }
        .onReceive(NotificationCenter.default.publisher(for: DepartmentStore.catalogDidChangeNotification)) { _ in
            normalizeExistingValues()
        }
    }

    /// Keeps saved department/position labels in sync with the catalog without auto-picking defaults.
    private func normalizeExistingValues() {
        let normalizedDept = DepartmentStore.normalize(department)
        guard !normalizedDept.isEmpty,
              let match = departments.first(where: { $0.name.caseInsensitiveCompare(normalizedDept) == .orderedSame })
        else {
            if !normalizedDept.isEmpty, !departments.isEmpty {
                // Unknown legacy department — keep text, clear position until user picks a catalog department.
                department = normalizedDept
            }
            return
        }

        department = match.name
        let normalizedPos = DepartmentStore.normalize(position)
        guard !normalizedPos.isEmpty else { return }

        let options = DepartmentStore.positions(for: match.name)
        if let posMatch = options.first(where: { $0.caseInsensitiveCompare(normalizedPos) == .orderedSame }) {
            position = posMatch
        }
    }
}

enum DepartmentSelectionValidator {
    static func isComplete(department: String, position: String) -> Bool {
        let dept = DepartmentStore.normalize(department)
        guard !dept.isEmpty else { return false }

        let pos = DepartmentStore.normalize(position)
        guard !pos.isEmpty else { return false }

        if DepartmentStore.isKnownDepartment(dept) {
            let options = DepartmentStore.positions(for: dept)
            if options.isEmpty {
                return true
            }
            return options.contains { $0.caseInsensitiveCompare(pos) == .orderedSame }
        }

        // Legacy free-text department/position from older records.
        return true
    }
}
