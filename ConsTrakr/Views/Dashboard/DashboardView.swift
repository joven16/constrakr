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

    private var todayTitle: String {
        Date().formatted(date: .complete, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    coverageHero
                    siteAttendanceSection
                    if !viewModel.sitesNeedingAttention.isEmpty {
                        attentionSection
                    }
                    rosterMetricsSection
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DashboardStatusIcons(
                        isOnline: viewModel.isOnline,
                        pendingSyncCount: viewModel.pendingSyncCount
                    ) {
                        tabRouter.selectedTab = .employees
                    }
                }
            }
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
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
            .refreshable {
                viewModel.refresh()
            }
        }
    }

    private var coverageHero: some View {
        let totals = viewModel.attendanceTotals
        let percent = totals.coveragePercent ?? 0
        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(coverageColor(for: percent), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: percent)
                VStack(spacing: 2) {
                    if totals.assigned > 0 {
                        Text("\(percent)%")
                            .font(.system(.title, design: .rounded).bold())
                        Text("\(totals.present)/\(totals.assigned)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.title.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 120, height: 120)

            Text("Today's coverage")
                .font(.headline)
            Text("\(todayTitle) · \(viewModel.employeeCount) employee\(viewModel.employeeCount == 1 ? "" : "s") · \(viewModel.siteSummaries.count) site\(viewModel.siteSummaries.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if totals.assigned > 0 {
                HStack(spacing: 8) {
                    heroChip(title: "Punches", value: "\(totals.punchCount)", tint: .blue)
                    heroChip(title: "Absent", value: "\(totals.absent)", tint: totals.absent > 0 ? .red : .secondary)
                    heroChip(title: "Incomplete", value: "\(totals.incomplete)", tint: totals.incomplete > 0 ? .orange : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func heroChip(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var siteAttendanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("By job site", systemImage: "building.2.fill")
                .font(.headline)

            if viewModel.siteSummaries.isEmpty {
                ContentUnavailableView(
                    "No job sites",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Add a job site under More → Job sites.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(viewModel.siteSummaries) { site in
                    SiteAttendanceCard(site: site) {
                        tabRouter.openDTR(forSiteId: site.id)
                    }
                }
                Text("Sorted by lowest coverage first")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(viewModel.sitesNeedingAttention) { site in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(coverageColor(for: site.coveragePercent ?? 0))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.siteName)
                            .font(.subheadline.weight(.semibold))
                        Text(attentionSummary(for: site))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let percent = site.coveragePercent {
                        Text("\(percent)%")
                            .font(.caption.bold())
                            .foregroundStyle(coverageColor(for: percent))
                    }
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func attentionSummary(for site: DashboardViewModel.SiteAttendanceSummary) -> String {
        var parts: [String] = []
        if site.absentCount > 0 {
            parts.append("\(site.absentCount) absent")
        }
        if site.incompleteCount > 0 {
            parts.append("\(site.incompleteCount) incomplete")
        }
        if parts.isEmpty, let percent = site.coveragePercent {
            parts.append("\(percent)% coverage")
        }
        return parts.joined(separator: " · ")
    }

    private var rosterMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Roster & sync", systemImage: "person.3.sequence.fill")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricTile(
                    title: "Enrolled",
                    value: "\(viewModel.enrolledCount)/\(viewModel.employeeCount)",
                    subtitle: "Face-ready for scanner",
                    tint: viewModel.enrolledCount == viewModel.employeeCount && viewModel.employeeCount > 0 ? .green : .indigo
                )
                metricTile(
                    title: "Unassigned",
                    value: "\(viewModel.unassignedCount)",
                    subtitle: "No job site yet",
                    tint: viewModel.unassignedCount > 0 ? .orange : .secondary
                )
                metricTile(
                    title: "Job sites",
                    value: "\(viewModel.siteSummaries.count)",
                    subtitle: "Active on device",
                    tint: .cyan
                )
                metricTile(
                    title: "Pending sync",
                    value: "\(viewModel.pendingSyncCount)",
                    subtitle: viewModel.isOnline ? "Tap sync icon above" : "Offline — will retry",
                    tint: viewModel.pendingSyncCount > 0 ? .orange : .secondary
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricTile(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func coverageColor(for percent: Int) -> Color {
        if percent >= 90 { return .green }
        if percent >= 70 { return .orange }
        return .red
    }
}

private struct DashboardStatusIcons: View {
    let isOnline: Bool
    let pendingSyncCount: Int
    let onSyncTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isOnline ? "wifi" : "wifi.slash")
                .foregroundStyle(isOnline ? .green : .secondary)
                .accessibilityLabel(isOnline ? "Online" : "Offline")

            Button(action: onSyncTap) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(pendingSyncCount > 0 ? .orange : .secondary)
                    if pendingSyncCount > 0 {
                        Text("\(min(pendingSyncCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.orange, in: Circle())
                            .offset(x: 8, y: -8)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pendingSyncCount > 0 ? "\(pendingSyncCount) pending sync items" : "Sync up to date")
        }
        .font(.subheadline)
    }
}

private struct SiteAttendanceCard: View {
    let site: DashboardViewModel.SiteAttendanceSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.siteName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if !site.locationLabel.isEmpty {
                            Text(site.locationLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if site.assignedCount > 0 {
                        VStack(alignment: .trailing, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(site.presentCount)")
                                    .font(.title2.bold())
                                    .foregroundStyle(.indigo)
                                Text("/\(site.assignedCount)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("punched")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No roster")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if site.assignedCount > 0, let percent = site.coveragePercent {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(coverageColor(for: site.coverageLevel))
                                .frame(width: geo.size.width * CGFloat(percent) / 100)
                        }
                    }
                    .frame(height: 8)

                    HStack(spacing: 8) {
                        Text("\(percent)% coverage")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(coverageColor(for: site.coverageLevel))
                        Spacer()
                        Text("\(site.punchCount) punch\(site.punchCount == 1 ? "" : "es")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if site.absentCount > 0 || site.incompleteCount > 0 {
                        HStack(spacing: 10) {
                            if site.absentCount > 0 {
                                Text("\(site.absentCount) absent")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            if site.incompleteCount > 0 {
                                Text("\(site.incompleteCount) incomplete")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else if site.punchCount > 0 {
                    Text("\(site.punchCount) punch\(site.punchCount == 1 ? "" : "es") today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No punches yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func coverageColor(for level: DashboardViewModel.SiteAttendanceSummary.CoverageLevel) -> Color {
        switch level {
        case .none: return .secondary
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
