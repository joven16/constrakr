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
                    Image(systemName: viewModel.isOnline ? "wifi" : "wifi.slash")
                        .foregroundStyle(viewModel.isOnline ? .green : .secondary)
                        .font(.subheadline)
                        .accessibilityLabel(viewModel.isOnline ? "Online" : "Offline")
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
                await viewModel.syncNow()
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
                        Text("\(totals.completionFractionLine)")
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
            Text("\(todayTitle) · \(viewModel.employeeCount) employee\(viewModel.employeeCount == 1 ? "" : "s") · \(defaultSiteSubtitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if totals.assigned > 0 {
                HStack(spacing: 8) {
                    heroChip(title: "Today", value: totals.inOutLine, tint: .blue)
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

    private var defaultSiteSubtitle: String {
        if let site = viewModel.defaultSiteSummary {
            return site.siteName
        }
        return "No default site"
    }

    private var siteAttendanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Default job site", systemImage: "building.2.fill")
                .font(.headline)

            if let site = viewModel.defaultSiteSummary {
                SiteAttendanceCard(
                    site: site,
                    isDefault: true
                ) {
                    tabRouter.openDTR()
                }
            } else {
                ContentUnavailableView(
                    "No default job site",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Set a default site under More → Job sites.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
                    title: "Default site",
                    value: viewModel.defaultSiteSummary?.siteName ?? "Not set",
                    subtitle: "Attendance & roster scope",
                    tint: viewModel.defaultSiteSummary == nil ? .orange : .cyan
                )
                metricTile(
                    title: "Pending sync",
                    value: "\(viewModel.pendingSyncCount)",
                    subtitle: viewModel.isOnline ? "Pull down to sync" : "Offline — will retry",
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

private struct SiteAttendanceCard: View {
    let site: DashboardViewModel.SiteAttendanceSummary
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(site.siteName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if isDefault {
                                Text("Default")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.teal)
                            }
                        }
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
                            if let percent = site.coveragePercent {
                                Text("\(percent)%")
                                    .font(.title2.bold())
                                    .foregroundStyle(coverageColor(for: site.coverageLevel))
                            }
                            Text(site.inOutLine)
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
                        Text(site.inOutLine)
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
                } else if site.checkInCount > 0 || site.checkOutCount > 0 {
                    Text(site.inOutLine)
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
            .overlay {
                if isDefault {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.teal.opacity(0.55), lineWidth: 2)
                }
            }
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
