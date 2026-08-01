//
//  AttendanceScannerView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData

struct AttendanceScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncQueue.self) private var syncQueue
    @State private var viewModel = AttendanceScannerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    CameraPreviewView(session: viewModel.cameraManager.session)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 3)
                        }

                    if let cameraError = viewModel.cameraError {
                        cameraErrorOverlay(cameraError)
                    } else {
                        scannerHUD
                    }
                }
                .padding(.horizontal)

                resultCard

                actionButtons
            }
            .padding(.vertical)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.teal.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                viewModel.pendingConfirmType?.confirmPrompt ?? "Confirm",
                isPresented: Binding(
                    get: { viewModel.pendingConfirmType != nil },
                    set: { if !$0 { viewModel.cancelConfirm() } }
                )
            ) {
                Button("Cancel", role: .cancel) { viewModel.cancelConfirm() }
                Button("Confirm") { viewModel.confirmPendingType() }
            } message: {
                Text(viewModel.pendingConfirmType?.confirmMessage ?? "")
            }
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
                Task { await viewModel.startCamera() }
            }
            .onDisappear {
                viewModel.stopCamera()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceHistoryDidClear)) { _ in
                viewModel.handleAttendanceHistoryCleared()
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    viewModel.requestConfirm(.checkIn)
                } label: {
                    Label(CheckType.checkIn.displayName, systemImage: CheckType.checkIn.systemImage)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(viewModel.isSessionActive || viewModel.isProcessing)

                Button {
                    viewModel.requestConfirm(.checkOut)
                } label: {
                    Label(CheckType.checkOut.displayName, systemImage: CheckType.checkOut.systemImage)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .disabled(viewModel.isSessionActive || viewModel.isProcessing)
            }

            if viewModel.isSessionActive {
                Button("Cancel Scan") {
                    viewModel.endSession(status: "Choose Time In or Time Out to begin.")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    private var borderColor: Color {
        if viewModel.successFlash { return .green }
        guard viewModel.isSessionActive else { return .white.opacity(0.35) }
        switch viewModel.recognitionState {
        case .noFace: return .white.opacity(0.4)
        case .unknownPerson, .poorQuality: return .orange
        case .verifying: return .yellow
        case .recognized: return .cyan
        case .alreadyRecorded: return .yellow
        case .idle: return viewModel.faceDetected ? .cyan : .white.opacity(0.4)
        }
    }

    private var scannerHUD: some View {
        VStack {
            if viewModel.isSessionActive {
                Text(viewModel.checkType.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
            }
            Spacer()
            // Only show the camera status label while a Time In/Out scan is active
            // (including the brief success / already-recorded result).
            if viewModel.isSessionActive || viewModel.recognitionState == .recognized || viewModel.recognitionState == .alreadyRecorded {
                Text(viewModel.statusMessage)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSessionActive)
        .animation(.easeInOut(duration: 0.25), value: viewModel.recognitionState == .recognized)
    }

    private func cameraErrorOverlay(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.isSessionActive {
                Text("Ready")
                    .font(.headline)
                Text("Tap Time In or Time Out, confirm, then look at the camera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                switch viewModel.recognitionState {
                case .noFace:
                    Text("No face detected")
                        .font(.headline)
                case .unknownPerson:
                    Text("Unknown Person")
                        .font(.headline)
                case .poorQuality:
                    Text(viewModel.statusMessage)
                        .font(.headline)
                case .verifying:
                    Text("Verifying…")
                        .font(.headline)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .recognized, .alreadyRecorded:
                    if viewModel.showsRecognitionDetails,
                       let name = viewModel.lastMatchName,
                       let confidence = viewModel.lastMatchConfidence {
                        Text(name)
                            .font(.title3.bold())
                        Text(viewModel.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(viewModel.recognitionState == .alreadyRecorded ? .orange : .primary)
                        Text(String(format: "Confidence %.0f%%", max(0, min(confidence, 1)) * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Awaiting face match")
                            .font(.headline)
                    }
                case .idle:
                    Text("Awaiting face match")
                        .font(.headline)
                    Text("Scanning for \(viewModel.checkType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
