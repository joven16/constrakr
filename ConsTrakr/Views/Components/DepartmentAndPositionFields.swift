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

    private var positionOptions: [String] {
        DepartmentStore.positions(for: department)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Department", selection: $department) {
                ForEach(departments) { category in
                    Text(category.name).tag(category.name)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: department) { _, _ in
                alignPositionForDepartment()
            }

            if positionOptions.isEmpty {
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
                        Text("\(position) (custom)").tag(position)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .onAppear { alignInitialState() }
        .onReceive(NotificationCenter.default.publisher(for: DepartmentStore.catalogDidChangeNotification)) { _ in
            alignInitialState()
        }
    }

    private func alignInitialState() {
        let normalizedDept = DepartmentStore.normalize(department)
        if normalizedDept.isEmpty, let first = departments.first {
            department = first.name
        } else if let match = departments.first(where: { $0.name.caseInsensitiveCompare(normalizedDept) == .orderedSame }) {
            department = match.name
        }
        alignPositionForDepartment()
    }

    private func alignPositionForDepartment() {
        let options = positionOptions
        let normalized = DepartmentStore.normalize(position)
        if normalized.isEmpty {
            position = options.first ?? ""
            return
        }
        if let match = options.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            position = match
        }
    }
}
