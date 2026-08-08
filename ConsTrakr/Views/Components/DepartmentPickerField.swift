//
//  DepartmentPickerField.swift
//  ConsTrakr
//

import SwiftUI

struct DepartmentPickerField: View {
    @Binding var department: String

    @State private var useOther = false
    @State private var otherText = ""

    private var presetOptions: [String] {
        DepartmentStore.allOptions
    }

    var body: some View {
        Group {
            if useOther {
                TextField("Department name", text: $otherText)
                    .textInputAutocapitalization(.words)
                    .onChange(of: otherText) { _, newValue in
                        department = DepartmentStore.normalize(newValue)
                    }
            } else {
                Picker("Department", selection: $department) {
                    ForEach(presetOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    Text(DepartmentDefaults.otherLabel).tag(DepartmentDefaults.otherLabel)
                }
                .pickerStyle(.menu)
                .onChange(of: department) { _, newValue in
                    if newValue == DepartmentDefaults.otherLabel {
                        useOther = true
                        otherText = ""
                        department = ""
                    }
                }
            }

            if useOther {
                Button("Choose from list") {
                    useOther = false
                    department = presetOptions.first ?? "General"
                }
                .font(.caption)
            }
        }
        .onAppear { alignInitialState() }
        .onReceive(NotificationCenter.default.publisher(for: DepartmentStore.catalogDidChangeNotification)) { _ in
            alignInitialState()
        }
    }

    private func alignInitialState() {
        let normalized = DepartmentStore.normalize(department)
        if normalized.isEmpty {
            department = presetOptions.first ?? "General"
            useOther = false
            return
        }
        if DepartmentStore.isPreset(normalized) {
            department = presetOptions.first { $0.caseInsensitiveCompare(normalized) == .orderedSame } ?? normalized
            useOther = false
        } else {
            useOther = true
            otherText = normalized
            department = normalized
        }
    }
}
