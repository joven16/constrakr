//
//  DTRView.swift
//  ConsTrakr
//
//  Daily Time Record — one row per employee with Time In / Time Out columns.
//

import SwiftUI
import SwiftData

struct DTRView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @Environment(AppAccessSession.self) private var access
    @State private var viewModel = DTRViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.viewSiteId != nil {
                    siteHeader
                    datePicker
                    syncStatusBar
                    dtrList
                } else {
                    sitePrompt
                }
            }
            .navigationTitle("DTR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ViewSiteFilterToolbar {
                        viewModel.refresh()
                    }
                }
            }
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
            }
            .onChange(of: syncQueue.pendingCount) { _, _ in
                viewModel.refreshDebounced()
            }
            .onChange(of: syncQueue.lastSyncDate) { _, _ in
                viewModel.refreshDebounced()
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceHistoryDidClear)) { _ in
                viewModel.refreshDebounced()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceDidChange)) { _ in
                viewModel.refreshDebounced()
            }
            .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
                viewModel.refreshDebounced()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppAccessSession.sessionDidChangeNotification)) { _ in
                viewModel.refreshDebounced()
            }
        }
    }

    private var siteHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedSiteTitle ?? "Job site")
                    .font(.subheadline.weight(.semibold))
                if !dtrSiteSubtitle.isEmpty {
                    Text(dtrSiteSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.teal.opacity(0.08))
    }

    private var dtrSiteSubtitle: String {
        if access.isViewingNonDefaultSite, let defaultTitle = access.operatorSiteTitle {
            return "Viewing only · scanner still uses \(defaultTitle)"
        }
        return ""
    }

    private var sitePrompt: some View {
        ContentUnavailableView(
            access.isAdminUnlocked ? "No job site selected" : "No default job site",
            systemImage: "mappin.slash",
            description: Text(access.isAdminUnlocked
                ? "Choose a site from the menu above to view daily time records for that crew."
                : "Set a default site under More → Job Sites to view daily time records for that crew.")
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
                Section {
                    ForEach(viewModel.rows) { row in
                        DTRCompactRow(row: row)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("Employee")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(CheckType.checkIn.displayName)
                            .frame(width: 56, alignment: .leading)
                        Text(CheckType.checkOut.displayName)
                            .frame(width: 56, alignment: .leading)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.syncNow()
        }
    }

    private var syncStatusBar: some View {
        HStack(spacing: 8) {
            Label("\(viewModel.pendingSyncCount) pending", systemImage: "arrow.up.circle")
                .font(.caption2.weight(.semibold))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(viewModel.isOnline ? "Online" : "Offline")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(viewModel.isOnline ? .green : .secondary)
            if let last = viewModel.lastSyncDate {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("Last sync \(last.attendanceDisplay)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var datePicker: some View {
        HStack {
            Text("Daily Time Record")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            DatePicker(
                "",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

private struct DTRCompactRow: View {
    let row: DTRViewModel.DTRRow

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.employeeName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(row.employeeCode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            compactPunch(time: row.timeIn, isCorrected: row.timeInCorrected)
            compactPunch(time: row.timeOut, isCorrected: row.timeOutCorrected)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func compactPunch(time: Date?, isCorrected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let time {
                Text(time.timeOnly)
                    .font(.caption.monospaced().weight(.semibold))
                if isCorrected {
                    Text("Adj")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, alignment: .leading)
    }
}
