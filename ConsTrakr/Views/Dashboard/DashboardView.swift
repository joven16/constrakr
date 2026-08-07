//
//  DashboardView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @Environment(AppTabRouter.self) private var tabRouter
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
                            tint: .cyan,
                            action: { tabRouter.selectedTab = .employees }
                        )
                        StatCard(
                            title: "Today",
                            value: "\(viewModel.todayAttendanceCount)",
                            systemImage: "calendar",
                            tint: .mint,
                            action: { tabRouter.selectedTab = .dtr }
                        )
                        StatCard(
                            title: "Pending Sync",
                            value: "\(viewModel.pendingSyncCount)",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .orange,
                            action: { tabRouter.selectedTab = .employees }
                        )
                        StatCard(
                            title: "Network",
                            value: viewModel.isOnline ? "Online" : "Offline",
                            systemImage: viewModel.isOnline ? "wifi" : "wifi.slash",
                            tint: viewModel.isOnline ? .green : .secondary,
                            action: { tabRouter.selectedTab = .more }
                        )
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recent Attendance")
                                .font(.headline)
                            Text("Latest punches on this device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.pendingSyncCount > 0 {
                            Text("\(viewModel.pendingSyncCount) pending · Pull down on Employees")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !viewModel.recentAttendance.isEmpty {
                            Button("See DTR") {
                                tabRouter.selectedTab = .dtr
                            }
                            .font(.caption)
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
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
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
