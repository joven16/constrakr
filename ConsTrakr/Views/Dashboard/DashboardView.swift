//
//  DashboardView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(
                            title: "Employees",
                            value: "\(viewModel.employeeCount)",
                            systemImage: "person.3.fill",
                            tint: .cyan
                        )
                        StatCard(
                            title: "Today",
                            value: "\(viewModel.todayAttendanceCount)",
                            systemImage: "calendar",
                            tint: .mint
                        )
                        StatCard(
                            title: "Pending Sync",
                            value: "\(viewModel.pendingSyncCount)",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .orange
                        )
                        StatCard(
                            title: "Network",
                            value: viewModel.isOnline ? "Online" : "Offline",
                            systemImage: viewModel.isOnline ? "wifi" : "wifi.slash",
                            tint: viewModel.isOnline ? .green : .secondary
                        )
                    }

                    HStack {
                        Text("Recent Attendance")
                            .font(.headline)
                        Spacer()
                        if viewModel.pendingSyncCount > 0 {
                            Text("\(viewModel.pendingSyncCount) pending · Sync on Employees")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if viewModel.recentAttendance.isEmpty {
                        ContentUnavailableView(
                            "No attendance yet",
                            systemImage: "clock",
                            description: Text("Use the Scanner tab to record check-ins.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(viewModel.recentAttendance) { item in
                            HStack {
                                Image(systemName: item.checkType.systemImage)
                                    .foregroundStyle(item.checkType == .checkIn ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline.weight(.semibold))
                                    Text("\(item.code) · \(item.timestamp.attendanceDisplay)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(status: item.syncStatus)
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.cyan.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("ConsTrakr")
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
            }
            // CHANGE: Keep Recent Attendance empty immediately after Clear History.
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceHistoryDidClear)) { _ in
                viewModel.refresh()
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }
}
