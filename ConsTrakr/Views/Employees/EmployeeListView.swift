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
    @State private var showSyncAlert = false

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
                    syncSection

                    if let report = viewModel.cloudReport {
                        Section {
                            LabeledContent("On IMS", value: "\(report.confirmedOnIMS)/\(report.localTotal)")
                            LabeledContent("Need upload", value: "\(report.needsUpload)")
                            LabeledContent("IMS server", value: "\(report.remoteTotal) (\(report.remoteRawCount) raw)")
                            LabeledContent("Checked", value: report.checkedAt.attendanceDisplay)
                            if let note = report.statusNote {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if report.needsUpload > 0 {
                                Text("Missing employees upload on the next sync (every \(SyncSettings.intervalLabel), or tap Sync in the toolbar).")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        } header: {
                            Text("IMS employee check")
                        }
                    }

                    ForEach(viewModel.employees, id: \.id) { employee in
                        NavigationLink {
                            EmployeeDetailView(
                                employee: employee,
                                cloudItem: viewModel.cloudItem(for: employee.id)
                            )
                        } label: {
                            EmployeeRow(
                                employee: employee,
                                cloudItem: viewModel.cloudItem(for: employee.id)
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
                        await viewModel.syncNow()
                        showSyncAlert = true
                    }
                } label: {
                    if syncQueue.isSyncing || viewModel.isCheckingCloud {
                        ProgressView()
                    } else {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(viewModel.isCheckingCloud || syncQueue.isSyncing)
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
            viewModel.applyCloudReport(syncQueue.lastEmployeeSyncReport)
            Task {
                await viewModel.checkCloudIfNeeded()
            }
        }
        .onChange(of: tabRouter.selectedTab) { _, tab in
            if tab == .employees {
                viewModel.refresh()
                viewModel.applyCloudReport(syncQueue.lastEmployeeSyncReport)
                Task {
                    await viewModel.checkCloudIfNeeded()
                }
            }
        }
        .onChange(of: syncQueue.lastEmployeeSyncReport?.checkedAt) { _, _ in
            viewModel.applyCloudReport(syncQueue.lastEmployeeSyncReport)
        }
        .onChange(of: syncQueue.lastSyncDate) { _, _ in
            viewModel.applyCloudReport(syncQueue.lastEmployeeSyncReport)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.employeesDidChange)) { _ in
            viewModel.refresh()
        }
        .refreshable {
            viewModel.refresh()
            await viewModel.checkCloudIfNeeded()
        }
        .alert("Sync", isPresented: $showSyncAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncAlertMessage)
        }
    }

    private var syncSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(syncQueue.pendingCount) pending", systemImage: "arrow.up.circle")
                    .font(.caption.weight(.semibold))
                if let last = syncQueue.lastSyncDate {
                    Text("Last sync: \(last.attendanceDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let attempt = syncQueue.lastSyncAttemptDate {
                    let stale = syncQueue.lastSyncDate.map { attempt.timeIntervalSince($0) > 30 } ?? true
                    if stale {
                        Text("Last attempt: \(attempt.attendanceDisplay)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Tap Sync in the toolbar to upload employees, face data, and DTR.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Auto sync every \(SyncSettings.intervalLabel) while app is open")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let error = syncQueue.lastError, !error.isEmpty,
                   !(NetworkMonitor.shared.isConnected && NetworkError.isOfflineMessage(error)) {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
    }

    private var syncAlertMessage: String {
        if let error = syncQueue.lastError, !error.isEmpty {
            return error
        }
        if let summary = syncQueue.lastPushSummary?.successMessage, !summary.isEmpty {
            return summary
        }
        if let report = viewModel.cloudReport?.summaryLine {
            return report
        }
        return "Sync finished."
    }

    private var deleteConfirmationMessage: String {
        if employeesPendingDeletion.count == 1, let employee = employeesPendingDeletion.first {
            return "\(employee.fullName) (\(employee.employeeCode)) will be removed from this device, including face enrollment data. If synced to IMS, their record stays on the server as Removed from app (attendance history preserved). The employee ID can be used again for a new registration."
        }
        return "\(employeesPendingDeletion.count) employees will be removed from this device, including face enrollment data. Synced records stay on IMS as Removed from app. Employee IDs can be reused for new registrations."
    }

    private func confirmDeleteEmployees() {
        let toDelete = employeesPendingDeletion
        employeesPendingDeletion = []
        showDeleteConfirmation = false
        for employee in toDelete {
            Task { await viewModel.delete(employee) }
        }
    }
}

private struct EmployeeRow: View {
    let employee: Employee
    let cloudItem: EmployeeSyncStatusItem?

    private var cloudStatus: EmployeeCloudStatus {
        cloudItem?.status ?? .notChecked
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(employee.fullName)
                    .font(.body.weight(.semibold))
                Text("\(employee.employeeCode) · \(employee.department)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let cloudItem {
                    Text(cloudItem.imsDateLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                CloudStatusBadge(status: cloudStatus)
                StatusBadge(status: cloudItem?.localSyncStatus ?? employee.syncStatus)
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
    var cloudItem: EmployeeSyncStatusItem?

    private var cloudStatus: EmployeeCloudStatus {
        cloudItem?.status ?? .notChecked
    }

    private var enrollmentPhotos: [(pose: FacePose, data: Data)] {
        EnrollmentPhotoStore.loadAll(employeeId: employee.id)
    }

    private var assignedSiteLabel: String {
        if let id = employee.assignedSiteId, let site = JobSiteStore.site(id: id) {
            return site.displayTitle
        }
        if let defaultSite = JobSiteStore.defaultSite {
            return "\(defaultSite.displayTitle) (default)"
        }
        return "Not set — tap Edit to assign"
    }

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Code", value: employee.employeeCode)
                LabeledContent("Name", value: employee.fullName)
                LabeledContent("Department", value: employee.department)
                LabeledContent("Job site", value: assignedSiteLabel)
                LabeledContent("Enrolled", value: employee.isEnrolled ? "Yes" : "No")
                LabeledContent("IMS status") {
                    CloudStatusBadge(status: cloudStatus)
                }
                if let cloudItem {
                    LabeledContent("Checked", value: cloudItem.checkedAt.attendanceDisplay)
                    if let imsUpdatedAt = cloudItem.imsUpdatedAt {
                        LabeledContent("IMS updated", value: imsUpdatedAt.attendanceDisplay)
                    }
                    LabeledContent("Local sync", value: cloudItem.localSyncStatus.displayName)
                }
                if let serverId = employee.serverId, !serverId.isEmpty {
                    LabeledContent("Server ID", value: serverId)
                }
                if cloudStatus == .needsUpload {
                    LabeledContent("Upload", value: employee.syncStatus.displayName)
                }
            }

            if employee.hasIdDocumentPhoto, let idType = employee.idDocumentType {
                Section("Government ID") {
                    LabeledContent("Type", value: idType.displayName)
                    if !employee.idDocumentNumber.isEmpty {
                        LabeledContent("Number", value: employee.idDocumentNumber)
                    }
                    if let data = IdDocumentPhotoStore.load(employeeId: employee.id),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
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
