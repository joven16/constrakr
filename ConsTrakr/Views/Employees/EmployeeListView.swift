//
//  EmployeeListView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData
import UIKit

struct EmployeeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @Environment(AppTabRouter.self) private var tabRouter
    @State private var viewModel = EmployeeListViewModel()
    @State private var employeesPendingDeletion: [Employee] = []
    @State private var showDeleteConfirmation = false
    @State private var showCloudCheckAlert = false

    var body: some View {
        NavigationStack {
            employeeListContent
        }
    }

    @ViewBuilder
    private var employeeListContent: some View {
        Group {
            if viewModel.employees.isEmpty {
                ContentUnavailableView(
                    "No Employees",
                    systemImage: "person.slash",
                    description: Text("Tap Register to enroll a new employee.")
                )
            } else {
                List {
                    if let report = viewModel.cloudReport {
                        Section {
                            LabeledContent("On IMS", value: "\(report.confirmedOnIMS)/\(report.localTotal)")
                            LabeledContent("Need upload", value: "\(report.needsUpload)")
                            LabeledContent("Server total", value: "\(report.remoteTotal)")
                        } header: {
                            Text("IMS employee check")
                        }
                    }

                    ForEach(viewModel.employees, id: \.id) { employee in
                        NavigationLink {
                            EmployeeDetailView(
                                employee: employee,
                                cloudStatus: viewModel.cloudStatus(for: employee.id)
                            )
                        } label: {
                            EmployeeRow(
                                employee: employee,
                                cloudStatus: viewModel.cloudStatus(for: employee.id)
                            )
                        }
                    }
                    .onDelete { indexSet in
                        employeesPendingDeletion = indexSet.map { viewModel.employees[$0] }
                        showDeleteConfirmation = true
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        await viewModel.checkCloudSync()
                        showCloudCheckAlert = true
                    }
                } label: {
                    if viewModel.isCheckingCloud {
                        ProgressView()
                    } else {
                        Label("Check IMS", systemImage: "checkmark.icloud")
                    }
                }
                .disabled(viewModel.isCheckingCloud)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EmployeeRegistrationView()
                } label: {
                    Label("Register", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search name, code, department")
        .alert("Delete employee?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                employeesPendingDeletion = []
            }
            Button("Delete", role: .destructive) {
                confirmDeleteEmployees()
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.refresh()
        }
        .onAppear {
            viewModel.configure(context: modelContext, syncQueue: syncQueue)
            Task { await viewModel.checkCloudSync() }
        }
        .onChange(of: tabRouter.selectedTab) { _, tab in
            if tab == .employees {
                viewModel.refresh()
                Task { await viewModel.checkCloudSync() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.employeesDidChange)) { _ in
            viewModel.refresh()
        }
        .refreshable {
            await viewModel.checkCloudSync()
            viewModel.refresh()
        }
        .alert("IMS Employee Check", isPresented: $showCloudCheckAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.cloudReport?.summaryLine ?? viewModel.errorMessage ?? "Could not check IMS.")
        }
    }

    private var deleteConfirmationMessage: String {
        if employeesPendingDeletion.count == 1, let employee = employeesPendingDeletion.first {
            return "\(employee.fullName) (\(employee.employeeCode)) will be removed from this device, including face enrollment data. This cannot be undone."
        }
        return "\(employeesPendingDeletion.count) employees will be removed from this device, including face enrollment data. This cannot be undone."
    }

    private func confirmDeleteEmployees() {
        let toDelete = employeesPendingDeletion
        employeesPendingDeletion = []
        showDeleteConfirmation = false
        for employee in toDelete {
            viewModel.delete(employee)
        }
    }
}

private struct EmployeeRow: View {
    let employee: Employee
    let cloudStatus: EmployeeCloudStatus

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(employee.fullName)
                    .font(.body.weight(.semibold))
                Text("\(employee.employeeCode) · \(employee.department)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                CloudStatusBadge(status: cloudStatus)
                if employee.isEnrolled {
                    Image(systemName: "faceid")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = EnrollmentPhotoStore.load(employeeId: employee.id, pose: .center),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.subheadline.bold())
                    .foregroundStyle(.cyan)
            }
        }
    }

    private var initials: String {
        let f = employee.firstName.prefix(1)
        let l = employee.lastName.prefix(1)
        return "\(f)\(l)".uppercased()
    }
}

struct EmployeeDetailView: View {
    let employee: Employee
    var cloudStatus: EmployeeCloudStatus = .notChecked

    private var enrollmentPhotos: [(pose: FacePose, data: Data)] {
        EnrollmentPhotoStore.loadAll(employeeId: employee.id)
    }

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Code", value: employee.employeeCode)
                LabeledContent("Name", value: employee.fullName)
                LabeledContent("Department", value: employee.department)
                LabeledContent("Enrolled", value: employee.isEnrolled ? "Yes" : "No")
                LabeledContent("IMS status") {
                    CloudStatusBadge(status: cloudStatus)
                }
                if let serverId = employee.serverId, !serverId.isEmpty {
                    LabeledContent("Server ID", value: serverId)
                }
                if cloudStatus == .needsUpload {
                    LabeledContent("Upload", value: employee.syncStatus.displayName)
                }
            }

            Section("Registered Faces") {
                if enrollmentPhotos.isEmpty {
                    Text("No registration photos available. Re-register this employee to capture pose images.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(enrollmentPhotos, id: \.pose) { item in
                            if let image = UIImage(data: item.data) {
                                VStack(spacing: 6) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 140)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Label(item.pose.displayName, systemImage: item.pose.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }

            Section("Face Embeddings") {
                if employee.faceEmbeddings.isEmpty {
                    Text("No embeddings enrolled")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(employee.faceEmbeddings, id: \.pose) { embedding in
                        HStack {
                            Label(embedding.pose.displayName, systemImage: embedding.pose.systemImage)
                            Spacer()
                            Text("\(embedding.values.count)-d")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Record") {
                LabeledContent("Created", value: employee.createdAt.attendanceDisplay)
                LabeledContent("Updated", value: employee.updatedAt.attendanceDisplay)
            }
        }
        .navigationTitle(employee.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EmployeeEditView(employee: employee)
                } label: {
                    Text("Edit")
                }
            }
        }
    }
}
