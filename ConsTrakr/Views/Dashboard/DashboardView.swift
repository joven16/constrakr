//
//  DashboardView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @Environment(AppAccessSession.self) private var access
    @State private var viewModel = DashboardViewModel()

    private var todayTitle: String {
        Date().formatted(date: .complete, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.viewSiteId == nil {
                        noSitePrompt
                    } else {
                        if let siteTitle = access.effectiveViewSiteTitle {
                            siteHeader(siteTitle)
                        }
                        coverageHero
                        if access.isViewingNonDefaultSite, let defaultTitle = access.operatorSiteTitle {
                            viewingOnlyNote(defaultTitle)
                        }
                        if !viewModel.sitesNeedingAttention.isEmpty {
                            attentionSection
                        }
                        if showsAttendanceProgress {
                            todayMetricsSection
                        }
                        rosterSyncSection
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ViewSiteFilterToolbar {
                        viewModel.refresh()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: connectionIconName)
                        .foregroundStyle(viewModel.isOnline ? .green : .secondary)
                        .font(.subheadline)
                        .accessibilityLabel(connectionAccessibilityLabel)
                }
            }
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
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
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.networkConnectivityDidChange)) { _ in
                viewModel.refreshDebounced()
            }
            .refreshable {
                await viewModel.syncNow()
            }
        }
    }

    private var connectionIconName: String {
        NetworkMonitor.shared.statusSymbolName
    }

    private var connectionAccessibilityLabel: String {
        NetworkMonitor.shared.statusAccessibilityLabel
    }

    private var noSitePrompt: some View {
        ContentUnavailableView(
            access.isAdminUnlocked ? "No job site selected" : "No default job site",
            systemImage: "mappin.and.ellipse",
            description: Text(access.isAdminUnlocked
                ? "Choose a site from the menu above, or set a default under More → Job Sites."
                : "Set a default site under More → Job sites.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func siteHeader(_ siteTitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(.teal)
            Text(access.isViewingNonDefaultSite ? "\(siteTitle) (viewing only)" : siteTitle)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func viewingOnlyNote(_ defaultTitle: String) -> some View {
        Label("Scanner still uses \(defaultTitle) for GPS check-in.", systemImage: "location.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var coverageHero: some View {
        let totals = viewModel.attendanceTotals
        let percent = totals.coveragePercent ?? 0
        return VStack(spacing: 14) {
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
                        Text(totals.completionFractionLine)
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

            VStack(spacing: 4) {
                Text("Today's coverage")
                    .font(.headline)
                Text("\(todayTitle) · \(viewModel.employeeCount) on roster")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if totals.assigned > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    heroChip(title: "Checked in", value: "\(totals.checkInCount)", tint: totals.checkInCount > 0 ? .blue : .secondary)
                    heroChip(title: "Checked out", value: "\(totals.checkOutCount)", tint: totals.checkOutCount > 0 ? .teal : .secondary)
                    heroChip(title: "Absent", value: "\(totals.absent)", tint: totals.absent > 0 ? .red : .secondary)
                    heroChip(title: "Incomplete", value: "\(totals.incomplete)", tint: totals.incomplete > 0 ? .orange : .secondary)
                    heroChip(title: "Assigned", value: "\(totals.assigned)", tint: .primary)
                    heroChip(title: "Complete", value: completeCountLine(totals), tint: percent >= 90 ? .green : .secondary)
                }
            }

        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func completeCountLine(_ totals: DashboardViewModel.AttendanceTotals) -> String {
        let complete = totals.assigned - totals.incomplete - totals.absent
        return "\(max(0, complete))"
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

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(viewModel.sitesNeedingAttention) { site in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attentionSummary(for: site))
                            .font(.subheadline.weight(.semibold))
                        if let percent = site.coveragePercent {
                            Text("\(percent)% coverage today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let percent = site.coveragePercent {
                        Text("\(percent)%")
                            .font(.title3.bold())
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
            return "\(percent)% coverage"
        }
        return parts.joined(separator: " · ")
    }

    private var showsAttendanceProgress: Bool {
        guard let site = viewModel.selectedSiteSummary else { return false }
        return site.assignedCount > 0 && site.coveragePercent != nil
    }

    private var todayMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today", systemImage: "clock.fill")
                .font(.headline)

            if let site = viewModel.selectedSiteSummary, site.assignedCount > 0, let percent = site.coveragePercent {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Attendance progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(site.inOutLine)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(coverageColor(for: percent))
                                .frame(width: geo.size.width * CGFloat(percent) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(percent)% of roster with full in/out today")
                        .font(.caption2)
                        .foregroundStyle(coverageColor(for: percent))
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var rosterSyncSection: some View {
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
                    title: "Not enrolled",
                    value: "\(max(0, viewModel.employeeCount - viewModel.enrolledCount))",
                    subtitle: "Need face registration",
                    tint: viewModel.enrolledCount < viewModel.employeeCount ? .orange : .secondary
                )
                metricTile(
                    title: "Unassigned",
                    value: "\(viewModel.unassignedCount)",
                    subtitle: "No job site on roster",
                    tint: viewModel.unassignedCount > 0 ? .orange : .secondary
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
