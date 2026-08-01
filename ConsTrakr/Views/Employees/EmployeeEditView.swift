//
//  EmployeeEditView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct EmployeeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let employee: Employee

    @State private var employeeCode = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var department = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isFormValid: Bool {
        !employeeCode.trimmingCharacters(in: .whitespaces).isEmpty
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Employee Code", text: $employeeCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)

                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)

                TextField("Department", text: $department)
                    .textContentType(.organizationName)
            } header: {
                Text("Employee Information")
            } footer: {
                Text("Face enrollment is unchanged. Edit profile details only.")
            }
        }
        .navigationTitle("Edit Employee")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(!isFormValid || isSaving)
            }
        }
        .onAppear {
            employeeCode = employee.employeeCode
            firstName = employee.firstName
            lastName = employee.lastName
            department = employee.department
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func saveChanges() {
        isSaving = true
        defer { isSaving = false }

        let service = EmployeeService(context: modelContext)
        do {
            try service.updateProfile(
                employee: employee,
                employeeCode: employeeCode,
                firstName: firstName,
                lastName: lastName,
                department: department
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
