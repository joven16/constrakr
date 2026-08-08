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

    let employee: Employee

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var department = ""
    @State private var position = ""
    @State private var assignedSiteId: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isAdminVerified = false
    @State private var showAdminCodePrompt = false
    @State private var adminGateError: String?

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && DepartmentSelectionValidator.isComplete(department: department, position: position)
    }

    var body: some View {
        Group {
            if isAdminVerified {
                editForm
            } else {
                adminGatePlaceholder
            }
        }
        .navigationTitle("Edit Employee")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !isAdminVerified else { return }
            presentAdminGateIfNeeded()
        }
        .fullScreenCover(isPresented: $showAdminCodePrompt) {
            AdminCodePromptSheet(
                title: "Edit employee",
                message: "Enter the admin code to edit employee records on this device.",
                onConfirm: { code in
                    try await AdminCodeService.verify(passcode: code)
                    isAdminVerified = true
                    showAdminCodePrompt = false
                    adminGateError = nil
                },
                onCancel: {
                    showAdminCodePrompt = false
                    dismiss()
                }
            )
        }
    }

    private var adminGatePlaceholder: some View {
        ContentUnavailableView {
            Label("Admin code required", systemImage: "lock.fill")
        } description: {
            Text(adminGateError ?? "Enter the 6-digit admin code to edit this employee.")
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
                JobSitePickerField(selectedSiteId: $assignedSiteId, allowNone: true)
            } header: {
                Text("Job Site")
            } footer: {
                Text("Pick where this employee must be for Time In / Time Out. Choose “None” to use the app default site from Settings.")
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
            assignedSiteId = employee.assignedSiteId
        }
        .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
            if assignedSiteId != nil, JobSiteStore.site(id: assignedSiteId) == nil {
                assignedSiteId = nil
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

    private func presentAdminGateIfNeeded() {
        adminGateError = nil
        do {
            try AdminCodeService.ensureChangeAllowed()
            showAdminCodePrompt = true
        } catch {
            adminGateError = error.localizedDescription
        }
    }

    private func saveChanges() {
        isSaving = true
        defer { isSaving = false }

        let service = EmployeeService(context: modelContext)
        do {
            try service.updateProfile(
                employee: employee,
                firstName: firstName,
                lastName: lastName,
                department: department,
                position: position,
                assignedSiteId: assignedSiteId
            )
            Task { await syncQueue.syncNow(mode: .quick, scope: .employees) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
