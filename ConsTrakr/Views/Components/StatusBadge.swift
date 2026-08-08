//
//  StatusBadge.swift
//  ConsTrakr
//

import SwiftUI

struct StatusBadge: View {
    let status: SyncStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}

struct CloudStatusBadge: View {
    let status: EmployeeCloudStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(foregroundColor.opacity(0.15), in: Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .onIMS: return .green
        case .needsUpload: return .orange
        case .notChecked: return .secondary
        }
    }
}

/// Compact list indicator: check when on IMS and synced, sync arrow when pending/upload needed.
struct EmployeeSyncIndicator: View {
    let cloudStatus: EmployeeCloudStatus
    let localStatus: SyncStatus

    var body: some View {
        Group {
            if isUpToDate {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if localStatus == .syncing {
                ProgressView()
                    .controlSize(.small)
            } else if localStatus == .failed {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(syncTint)
            }
        }
        .font(.title3)
        .accessibilityLabel(accessibilityLabel)
    }

    var isUpToDate: Bool {
        cloudStatus == .onIMS && localStatus == .synced
    }

    private var syncTint: Color {
        switch localStatus {
        case .syncing: return .blue
        case .pending: return .orange
        default: return .orange
        }
    }

    private var accessibilityLabel: String {
        if isUpToDate { return "Up to date on IMS" }
        if localStatus == .failed { return "Sync failed" }
        if localStatus == .syncing { return "Syncing" }
        if cloudStatus == .needsUpload { return "Not on IMS, needs upload" }
        return "Pending sync"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title, design: .rounded).bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
