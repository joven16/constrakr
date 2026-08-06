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
    @State private var viewModel = DTRViewModel()
    @State private var showSyncAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                datePicker
                syncBar
                columnHeader
                if viewModel.rows.isEmpty {
                    ContentUnavailableView(
                        "No DTR for this date",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Time In and Time Out records for \(viewModel.dayTitle) will appear here.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(viewModel.rows) { row in
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
                                    color: .green
                                )
                                timeColumn(
                                    title: CheckType.checkOut.displayName,
                                    time: row.timeOut,
                                    attendanceId: row.timeOutAttendanceId,
                                    color: .orange
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("DTR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runSync(showAlert: true) }
                    } label: {
                        if viewModel.isSyncing {
                            ProgressView()
                        } else {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isSyncing)
                }
            }
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
            }
            .onChange(of: syncQueue.pendingCount) { _, _ in
                viewModel.refresh()
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceHistoryDidClear)) { _ in
                viewModel.refresh()
            }
            .refreshable {
                await runSync(showAlert: false)
            }
            .alert("Sync", isPresented: $showSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.syncStatusMessage ?? "")
            }
        }
    }

    private func runSync(showAlert: Bool) async {
        await viewModel.syncNow()
        if showAlert {
            showSyncAlert = true
        }
    }

    private var syncBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("\(viewModel.pendingSyncCount) pending", systemImage: "arrow.up.circle")
                        .font(.caption.weight(.semibold))
                    Text(viewModel.isOnline ? "Online" : "Offline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.isOnline ? .green : .secondary)
                }
                if let report = viewModel.cloudReport {
                    Text("Employees: \(report.confirmedOnIMS)/\(report.localTotal) on IMS")
                        .font(.caption2)
                        .foregroundStyle(report.confirmedOnIMS == report.localTotal ? .green : .orange)
                    Text("Checked: \(report.checkedAt.attendanceDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let last = viewModel.lastSyncDate {
                    Text("Last sync: \(last.attendanceDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Uploads employees, face data, and DTR to IMS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await runSync(showAlert: true) }
            } label: {
                if viewModel.isSyncing {
                    ProgressView()
                        .frame(width: 44)
                } else {
                    Text("Sync Now")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(viewModel.isSyncing)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var datePicker: some View {
        DatePicker(
            "DTR Date",
            selection: $viewModel.selectedDate,
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .padding()
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

    private func timeColumn(title: String, time: Date?, attendanceId: UUID?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
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
