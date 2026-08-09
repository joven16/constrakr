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
    @Environment(AppAccessSession.self) private var access
    @State private var viewModel = EmployeeListViewModel()
    @State private var employeesPendingDeletion: [Employee] = []
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            employeeListContent
        }
    }

    @ViewBuilder
    private var employeeListContent: some View {
        employeeList
            .listStyle(.plain)
            .searchable(text: $viewModel.searchText, prompt: "Search name, code, department")
            .navigationTitle("Employees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { registerToolbar }
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
                viewModel.searchTextChanged()
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
                viewModel.refreshDebounced()
            }
            .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
                viewModel.refreshDebounced()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppAccessSession.sessionDidChangeNotification)) { _ in
                viewModel.refreshDebounced()
            }
            .refreshable {
                await viewModel.syncNow()
            }
    }

    private var employeeList: some View {
        List {
            if viewModel.viewSiteId == nil {
                Section {
                    Label {
                        Text(access.isAdminUnlocked
                            ? "Choose a site from the menu above, or set a default under More → Job Sites."
                            : "Set a default job site under More → Unlock admin → Job Sites.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.orange)
                    }
                }
            } else if let siteTitle = viewModel.viewSiteTitle {
                Section {
                    Label {
                        Text(access.isViewingNonDefaultSite ? "\(siteTitle) (viewing only)" : siteTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(.teal)
                    }
                }
            }

            if shouldShowSyncBanner {
                syncBanner
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            if viewModel.viewSiteId != nil && viewModel.employees.isEmpty {
                ContentUnavailableView(
                    "No Employees",
                    systemImage: "person.slash",
                    description: Text("No one is assigned to this job site yet, or pull down to sync from the server.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if viewModel.viewSiteId == nil && viewModel.employees.isEmpty {
                ContentUnavailableView(
                    "No Job Site",
                    systemImage: "mappin.slash",
                    description: Text(access.isAdminUnlocked
                        ? "Choose a site from the menu above."
                        : "Choose a default job site under More → Job Sites.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if !viewModel.employees.isEmpty {
                employeeRows
            }
        }
    }

    private var employeeRows: some View {
        Group {
            if access.canDeleteEmployees() {
                ForEach(viewModel.employees, id: \.id) { employee in
                    EmployeeNavigationRow(
                        employee: employee,
                        cloudItem: viewModel.cloudItem(for: employee.id),
                        canEdit: access.canEditEmployee(employee)
                    )
                }
                .onDelete { indexSet in
                    employeesPendingDeletion = indexSet.map { viewModel.employees[$0] }
                    showDeleteConfirmation = true
                }
            } else {
                ForEach(viewModel.employees, id: \.id) { employee in
                    EmployeeNavigationRow(
                        employee: employee,
                        cloudItem: viewModel.cloudItem(for: employee.id),
                        canEdit: access.canEditEmployee(employee)
                    )
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var registerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ViewSiteFilterToolbar {
                viewModel.refresh()
            }
        }
        if !DeviceAccessGuard.isBlocked, access.canRegisterEmployee() {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EmployeeRegistrationView()
                } label: {
                    Label("Register", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
    }

    private var shouldShowSyncBanner: Bool {
        syncQueue.isSyncing
            || viewModel.isCheckingCloud
            || syncQueue.pendingCount > 0
            || syncWarningLine != nil
    }

    private var syncBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            if syncQueue.isSyncing || viewModel.isCheckingCloud {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(syncStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = syncWarningLine {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var syncStatusLine: String {
        if let progress = syncQueue.syncProgressMessage, !progress.isEmpty {
            return progress
        }
        var parts: [String] = []
        if syncQueue.pendingCount > 0 {
            parts.append("\(syncQueue.pendingCount) pending")
        }
        if let last = syncQueue.lastSyncDate {
            parts.append("Last sync \(last.attendanceDisplay)")
        } else {
            parts.append("Not synced yet")
        }
        parts.append("Pull down to sync")
        return parts.joined(separator: " · ")
    }

    private var syncWarningLine: String? {
        if let error = syncQueue.lastError, !error.isEmpty,
           !(NetworkMonitor.shared.isConnected && NetworkError.isOfflineMessage(error)) {
            return error
        }
        if let note = viewModel.cloudReport?.statusNote {
            return note
        }
        if let needsUpload = viewModel.cloudReport?.needsUpload, needsUpload > 0 {
            return "\(needsUpload) employee\(needsUpload == 1 ? "" : "s") need upload — pull down to sync."
        }
        return nil
    }

    private var deleteConfirmationMessage: String {
        if employeesPendingDeletion.count == 1, let employee = employeesPendingDeletion.first {
            return "\(employee.fullName) (\(employee.employeeCode)) will be removed from this device, including face enrollment data. If synced to the server, their record stays on the server as Removed from app (attendance history preserved). The employee ID can be used again for a new registration."
        }
        return "\(employeesPendingDeletion.count) employees will be removed from this device, including face enrollment data. Synced records stay on the server as Removed from app. Employee IDs can be reused for new registrations."
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

private struct EmployeeNavigationRow: View {
    let employee: Employee
    let cloudItem: EmployeeSyncStatusItem?
    var canEdit: Bool = true

    var body: some View {
        NavigationLink {
            EmployeeDetailView(employee: employee, cloudItem: cloudItem, canEdit: canEdit)
        } label: {
            EmployeeRow(employee: employee, cloudItem: cloudItem)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
        .listRowSeparatorTint(Color(.separator))
    }
}

private struct EmployeeRow: View {
    let employee: Employee
    let cloudItem: EmployeeSyncStatusItem?

    private var cloudStatus: EmployeeCloudStatus {
        cloudItem?.status ?? .notChecked
    }

    private var localStatus: SyncStatus {
        cloudItem?.localSyncStatus ?? employee.syncStatus
    }

    private var syncIndicator: EmployeeSyncIndicator {
        EmployeeSyncIndicator(cloudStatus: cloudStatus, localStatus: localStatus)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(employee.fullName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            syncIndicator
        }
    }

    private var subtitle: String {
        siteLabel
    }

    private var siteLabel: String {
        if !employee.assignedSiteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return employee.assignedSiteName
        }
        if let id = employee.assignedSiteId, let site = JobSiteStore.site(id: id) {
            return site.displayTitle
        }
        if let defaultSite = JobSiteStore.defaultSite {
            return "\(defaultSite.displayTitle) (default)"
        }
        return "No job site assigned"
    }

    private var avatar: some View {
        EmployeeAvatarView(employee: employee)
    }
}

struct EmployeeDetailView: View {
    let employee: Employee
    var cloudItem: EmployeeSyncStatusItem?
    var canEdit: Bool = true

    @Environment(AppAccessSession.self) private var access

    @State private var faceGallery: FaceGallerySession?
    @State private var faceGalleryItems: [PhotoGalleryItem] = []
    @State private var idDocumentImage: UIImage?

    private var cloudStatus: EmployeeCloudStatus {
        cloudItem?.status ?? .notChecked
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

    private var syncSummaryText: String {
        let local = cloudItem?.localSyncStatus ?? employee.syncStatus
        let indicator = EmployeeSyncIndicator(cloudStatus: cloudStatus, localStatus: local)
        if indicator.isUpToDate { return "Up to date on server" }
        if local == .failed { return "Sync failed — pull down to retry" }
        if local == .syncing { return "Syncing…" }
        if cloudStatus == .needsUpload { return "Not on server — pull down to upload" }
        if cloudStatus == .notChecked {
            if cloudItem?.checkedWhileOffline == true {
                return "Offline — pull down when online"
            }
            return "Pull down to refresh sync status"
        }
        if local == .pending { return "Pending upload" }
        return "Pull down to sync"
    }

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Code", value: employee.employeeCode)
                LabeledContent("Name", value: employee.fullName)
                LabeledContent("Department", value: employee.department)
                LabeledContent("Job site", value: assignedSiteLabel)
                LabeledContent("Enrolled", value: employee.isEnrolled ? "Yes" : "No")
                LabeledContent("Sync") {
                    HStack(spacing: 8) {
                        EmployeeSyncIndicator(
                            cloudStatus: cloudStatus,
                            localStatus: cloudItem?.localSyncStatus ?? employee.syncStatus
                        )
                        Text(syncSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if employee.hasIdDocumentPhoto || employee.idDocumentType != nil {
                Section("Government ID") {
                    if let idType = employee.idDocumentType {
                        LabeledContent("Type", value: idType.displayName)
                    }
                    if !employee.idDocumentNumber.isEmpty {
                        LabeledContent("Number", value: employee.idDocumentNumber)
                    }
                    if let capturedAt = employee.idDocumentCapturedAt {
                        LabeledContent("Captured", value: capturedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let idDocumentImage {
                        EmployeePhotoPreview(image: idDocumentImage, title: "Government ID")
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    } else if employee.hasIdDocumentPhoto {
                        Text("ID photo not stored on this device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if faceGalleryItems.isEmpty {
                    Text("No registration photos on this device.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    Text("Tap a photo to open the gallery. Swipe left or right to browse each pose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(Array(faceGalleryItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                faceGallery = FaceGallerySession(startIndex: index)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFill()
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(item.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            } header: {
                Text("Registered Faces")
            }

            if cloudItem != nil || !employee.faceEmbeddings.isEmpty || (employee.serverId?.isEmpty == false) {
                Section {
                    DisclosureGroup("Sync & technical details") {
                        if let cloudItem {
                            LabeledContent("Checked", value: cloudItem.checkedAt.attendanceDisplay)
                            if let imsUpdatedAt = cloudItem.imsUpdatedAt {
                                LabeledContent("Server updated", value: imsUpdatedAt.attendanceDisplay)
                            }
                            LabeledContent("Local sync", value: cloudItem.localSyncStatus.displayName)
                        }
                        if let serverId = employee.serverId, !serverId.isEmpty {
                            LabeledContent("Server ID", value: serverId)
                        }
                        if employee.faceEmbeddings.isEmpty {
                            Text("No face embeddings enrolled")
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
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        EmployeeEditView(employee: employee)
                    } label: {
                        Text("Edit")
                    }
                }
            }
        }
        .fullScreenCover(item: $faceGallery) { session in
            PhotoGalleryLightboxView(items: faceGalleryItems, initialIndex: session.startIndex)
        }
        .task(id: employee.id) {
            let employeeId = employee.id
            async let galleryTask = Task.detached(priority: .utility) {
                FacePose.enrollmentOrder.compactMap { pose -> PhotoGalleryItem? in
                    guard
                        let data = EnrollmentPhotoStore.load(employeeId: employeeId, pose: pose),
                        let image = UIImage(data: data)
                    else { return nil }
                    return PhotoGalleryItem(id: pose.rawValue, image: image, title: pose.displayName)
                }
            }.value
            async let idPhotoTask = Task.detached(priority: .utility) {
                guard
                    let data = IdDocumentPhotoStore.load(employeeId: employeeId),
                    let image = UIImage(data: data)
                else { return nil as UIImage? }
                return image
            }.value

            faceGalleryItems = await galleryTask
            idDocumentImage = await idPhotoTask
        }
    }
}

private struct FaceGallerySession: Identifiable {
    let id = UUID()
    let startIndex: Int
}

private struct EmployeePhotoPreview: View {
    let image: UIImage
    let title: String
    @State private var showFullScreen = false

    var body: some View {
        Button {
            showFullScreen = true
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showFullScreen) {
            PhotoLightboxView(image: image, title: title)
        }
    }
}
