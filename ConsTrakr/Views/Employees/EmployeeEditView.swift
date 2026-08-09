//
//  EmployeeEditView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct EmployeeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncQueue.self) private var syncQueue
    @Environment(AppAccessSession.self) private var access

    let employee: Employee

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var department = ""
    @State private var position = ""
    @State private var assignedSiteId: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && DepartmentSelectionValidator.isComplete(department: department, position: position)
    }

    private var usesOperatorSiteLock: Bool {
        !access.isAdminUnlocked
    }

    private var lockedOperatorSiteId: UUID? {
        usesOperatorSiteLock ? access.operatorSiteId : nil
    }

    var body: some View {
        Group {
            if access.canEditEmployee(employee) {
                editForm
            } else {
                accessDeniedView
            }
        }
        .navigationTitle("Edit Employee")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accessDeniedView: some View {
        ContentUnavailableView {
            Label("Not allowed", systemImage: "hand.raised.fill")
        } description: {
            Text("You can only edit employees assigned to \(access.operatorSiteTitle ?? "your site"). Unlock admin to edit other sites.")
        }
    }

    private var editForm: some View {
        Form {
            Section {
                LabeledContent("Employee Code", value: employee.employeeCode)

                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)

                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)

                DepartmentAndPositionFields(department: $department, position: $position)
            } header: {
                Text("Employee Information")
            } footer: {
                Text("Pick department first, then position. Employee ID cannot be changed. Face enrollment is unchanged.")
            }

            Section {
                JobSitePickerField(
                    selectedSiteId: $assignedSiteId,
                    allowNone: access.isAdminUnlocked,
                    lockedSiteId: lockedOperatorSiteId
                )
            } header: {
                Text("Job Site")
            } footer: {
                if usesOperatorSiteLock {
                    Text("Operators keep employees on the device’s current site.")
                } else {
                    Text("Pick where this employee must be for Time In / Time Out. Choose “None” to use the app default site from Settings.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(!isFormValid || isSaving)
            }
        }
        .onAppear {
            firstName = employee.firstName
            lastName = employee.lastName
            department = employee.department
            position = employee.position
            assignedSiteId = employee.assignedSiteId ?? access.operatorSiteId
            if let lockedOperatorSiteId {
                assignedSiteId = lockedOperatorSiteId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
            if assignedSiteId != nil, JobSiteStore.site(id: assignedSiteId) == nil {
                assignedSiteId = lockedOperatorSiteId ?? access.operatorSiteId
            }
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

        let siteId = lockedOperatorSiteId ?? assignedSiteId
        let service = EmployeeService(context: modelContext)
        do {
            try service.updateProfile(
                employee: employee,
                firstName: firstName,
                lastName: lastName,
                department: department,
                position: position,
                assignedSiteId: siteId
            )
            Task { await syncQueue.syncNow(mode: .quick, scope: .employees) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
