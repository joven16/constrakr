//
//  DTRView.swift
//  ConsTrakr
//
//  Daily Time Record — one row per employee with Time In / Time Out columns.
//

import SwiftUI
import SwiftData
import UIKit

struct DTRView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @Environment(AppTabRouter.self) private var tabRouter
    @State private var viewModel = DTRViewModel()

    private var siteSelection: Binding<UUID?> {
        Binding(
            get: { tabRouter.dtrSiteFilterId },
            set: { newValue in
                tabRouter.dtrSiteFilterId = newValue
                viewModel.selectedSiteId = newValue
                viewModel.refresh()
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sitePickerSection
                if tabRouter.dtrSiteFilterId != nil {
                    datePicker
                    syncStatusBar
                    columnHeader
                    dtrList
                } else {
                    sitePrompt
                }
            }
            .navigationTitle("DTR")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.selectedSiteId = tabRouter.dtrSiteFilterId
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
            }
            .onChange(of: tabRouter.dtrSiteFilterId) { _, newValue in
                viewModel.selectedSiteId = newValue
                viewModel.refresh()
            }
            .onChange(of: syncQueue.pendingCount) { _, _ in
                viewModel.refresh()
            }
            .onChange(of: syncQueue.lastSyncDate) { _, _ in
                viewModel.refresh()
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceHistoryDidClear)) { _ in
                viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceDidChange)) { _ in
                viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
                viewModel.refresh()
            }
        }
    }

    private var sitePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Job site")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            JobSitePickerField(
                selectedSiteId: siteSelection,
                coordinateSitesOnly: false
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }

    private var sitePrompt: some View {
        ContentUnavailableView(
            "Select a job site",
            systemImage: "building.2",
            description: Text("Choose a site above to view daily time records for assigned employees.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dtrList: some View {
        List {
            if viewModel.rows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No DTR for this date",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No assigned employees or punches for \(viewModel.dayTitle).")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(viewModel.rows) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(row.employeeName)
                            .font(.body.weight(.semibold))
                        Text(row.employeeCode)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(alignment: .top, spacing: 12) {
                            timeColumn(
                                title: CheckType.checkIn.displayName,
                                time: row.timeIn,
                                attendanceId: row.timeInAttendanceId,
                                isCorrected: row.timeInCorrected,
                                color: .green
                            )
                            timeColumn(
                                title: CheckType.checkOut.displayName,
                                time: row.timeOut,
                                attendanceId: row.timeOutAttendanceId,
                                isCorrected: row.timeOutCorrected,
                                color: .orange
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.syncNow()
        }
    }

    private var syncStatusBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let siteTitle = viewModel.selectedSiteTitle {
                    Text(siteTitle)
                        .font(.caption.weight(.semibold))
                }
                HStack(spacing: 8) {
                    Label("\(viewModel.pendingSyncCount) pending", systemImage: "arrow.up.circle")
                        .font(.caption.weight(.semibold))
                    Text(viewModel.isOnline ? "Online" : "Offline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.isOnline ? .green : .secondary)
                }
                if let last = viewModel.lastSyncDate {
                    Text("Last sync: \(last.attendanceDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Pull down to sync punches and server corrections.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Time Record")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            DatePicker(
                "",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text(CheckType.checkIn.displayName)
                .frame(maxWidth: .infinity)
            Text(CheckType.checkOut.displayName)
                .frame(maxWidth: .infinity)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
    }

    private func timeColumn(
        title: String,
        time: Date?,
        attendanceId: UUID?,
        isCorrected: Bool,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                if isCorrected {
                    Text("Corrected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
            if let time {
                HStack(spacing: 8) {
                    punchThumb(attendanceId)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(time.timeOnly)
                            .font(.title3.monospaced().weight(.semibold))
                        Text(time.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func punchThumb(_ attendanceId: UUID?) -> some View {
        if let attendanceId,
           let data = AttendancePhotoStore.load(attendanceId: attendanceId),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
