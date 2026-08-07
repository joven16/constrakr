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
