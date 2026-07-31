//
//  AttendanceHistoryView.swift
//  ConsTrac
//
//  Sync History under More — shows attendance sync status.
//  Clear History does NOT delete DTR Time In / Time Out records.
//

import SwiftUI
import SwiftData

struct AttendanceHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = AttendanceHistoryViewModel()
    @State private var confirmClear = false
    var embedsNavigation: Bool = true

    var body: some View {
        Group {
            if embedsNavigation {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            filters
            if viewModel.records.isEmpty {
                ContentUnavailableView(
                    "No Sync Records",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Pending or failed sync items appear here. Daily Time In / Time Out live in DTR.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(viewModel.records) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.checkType.systemImage)
                            .font(.title3)
                            .foregroundStyle(item.checkType == .checkIn ? .green : .orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.employeeName)
                                .font(.body.weight(.semibold))
                            Text("\(item.employeeCode) · \(item.checkType.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.timestamp.attendanceDisplay)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: item.syncStatus)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Sync History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear History", role: .destructive) {
                    confirmClear = true
                }
                .disabled(viewModel.records.isEmpty)
            }
        }
        .alert("Clear sync history list?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear List", role: .destructive) {
                viewModel.clearHistory()
            }
        } message: {
            Text("This only clears the sync status list view. Time In and Time Out records in DTR are kept.")
        }
        .onAppear {
            viewModel.configure(context: modelContext)
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("Type", selection: Binding(
                get: { viewModel.filterCheckType },
                set: { viewModel.filterCheckType = $0; viewModel.refresh() }
            )) {
                Text("All").tag(Optional<CheckType>.none)
                ForEach(CheckType.allCases) { type in
                    Text(type.displayName).tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)

            Toggle("Pending / Failed only", isOn: Binding(
                get: { viewModel.showPendingOnly },
                set: { viewModel.showPendingOnly = $0; viewModel.refresh() }
            ))
            .font(.subheadline)
        }
        .padding()
    }
}
