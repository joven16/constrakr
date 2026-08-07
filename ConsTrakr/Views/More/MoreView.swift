//
//  MoreView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct MoreView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var confirmClearDTR = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    JobSitesListView()
                } label: {
                    Label("Job Sites", systemImage: "mappin.and.ellipse")
                }

                NavigationLink {
                    SettingsView(embedsNavigation: false)
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }

                NavigationLink {
                    AttendanceHistoryView(embedsNavigation: false)
                } label: {
                    Label("Sync History", systemImage: "clock.arrow.circlepath")
                }

                Section {
                    Button(role: .destructive) {
                        confirmClearDTR = true
                    } label: {
                        Label("Clear DTR", systemImage: "trash")
                    }
                } footer: {
                    Text("Testing only — deletes all Time In and Time Out records on this device.")
                }

                Section("Credits") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppConstants.appName)
                            .font(.headline)
                        Text("by Joven Lusterio")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("More")
            .alert("Clear all DTR records?", isPresented: $confirmClearDTR) {
                Button("Cancel", role: .cancel) {}
                Button("Clear DTR", role: .destructive) {
                    clearDTR()
                }
            } message: {
                Text("This permanently deletes every Time In and Time Out record. Use for testing so you do not need to reinstall the app.")
            }
            .alert("DTR Cleared", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) { statusMessage = nil }
            } message: {
                Text(statusMessage ?? "")
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func clearDTR() {
        do {
            try AttendanceService(context: modelContext).clearHistory()
            statusMessage = "All Time In and Time Out records were cleared."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
