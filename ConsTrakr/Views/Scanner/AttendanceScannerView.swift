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
    /// Locked on first layout so the preview never shrinks when status text grows.
    @State private var lockedCameraSize: CGSize?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let horizontalPad: CGFloat = 16
                let computedWidth = max(0, geo.size.width - horizontalPad * 2)
                let computedHeight = computedWidth * 4 / 3
                let cameraWidth = lockedCameraSize?.width ?? computedWidth
                let cameraHeight = lockedCameraSize?.height ?? computedHeight

                VStack(spacing: 0) {
                    cameraStage
                        .frame(width: cameraWidth, height: cameraHeight)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(2)
                        .padding(.horizontal, horizontalPad)
                        .padding(.top, 12)

                    ScrollView {
                        statusPanel
                            .padding(.horizontal, horizontalPad)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)

                    actionButtons
                        .padding(.horizontal, horizontalPad)
                        .padding(.bottom, 12)
                        .layoutPriority(1)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .onAppear {
                    lockCameraSizeIfNeeded(width: computedWidth, height: computedHeight)
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    guard lockedCameraSize == nil else { return }
                    let width = max(0, newWidth - horizontalPad * 2)
                    lockCameraSizeIfNeeded(width: width, height: width * 4 / 3)
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.teal.opacity(0.07)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: Binding(
                get: { viewModel.isAwaitingSupervisorPIN },
                set: { if !$0 { viewModel.cancelSupervisorPIN() } }
            )) {
                supervisorPINSheet
            }
            .alert(
                "Off site",
                isPresented: Binding(
                    get: { viewModel.siteGateMessage != nil },
                    set: { if !$0 { viewModel.dismissSiteGateMessage() } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.dismissSiteGateMessage() }
            } message: {
                Text(viewModel.siteGateMessage ?? "")
            }
            .onAppear {
                viewModel.configure(context: modelContext, syncQueue: syncQueue)
                ClockIntegrityGuard.shared.bootstrapIfNeeded()
                viewModel.refreshScannerReadySteps()
                Task { await viewModel.startCamera() }
            }
            .onDisappear {
                viewModel.stopCamera()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceHistoryDidClear)) { _ in
                viewModel.handleAttendanceHistoryCleared()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.attendanceDidChange)) { _ in
                viewModel.handleAttendanceDidChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: JobSiteStore.sitesDidChangeNotification)) { _ in
                Task { await viewModel.refreshScannerLocationGate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: FaceScanSettings.settingsDidChangeNotification)) { _ in
                viewModel.refreshScannerReadySteps()
            }
        }
    }

    // MARK: - Camera

    private var cameraStage: some View {
        ZStack {
            CameraPreviewView(session: viewModel.cameraManager.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 3)
                }

            if let cameraError = viewModel.cameraError {
                cameraErrorOverlay(cameraError)
            } else if viewModel.isScannerLocationBlocked && !viewModel.isSessionActive {
                locationBlockedOverlay
            } else {
                FaceGuideOverlay(
                    isConditionMet: viewModel.guideConditionMet || viewModel.successFlash,
                    caption: viewModel.primaryInstruction,
                    challenge: viewModel.overlayChallenge,
                    needsLookStraight: viewModel.livenessNeedsLookStraight,
                    showsNoseTarget: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack {
                    topChip
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var topChip: some View {
        VStack(spacing: 6) {
            operatingSiteChip
            if viewModel.isSessionActive {
                sessionChip
            }
        }
    }

    private var operatingSiteChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
            Text(viewModel.operatingSiteLabel)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
    }

    private var sessionChip: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.checkType.systemImage)
            Text(viewModel.checkType.displayName)
                .fontWeight(.bold)

            if !viewModel.livenessPassed {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(viewModel.livenessStepLabel)
                    .fontWeight(.semibold)
            } else if viewModel.recognitionState == .verifying {
                Text("· Verifying")
                    .fontWeight(.semibold)
            } else if viewModel.successFlash {
                Text("· Saved")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
    }

    // MARK: - Status

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: viewModel.isSessionActive ? 12 : 8) {
            if viewModel.isSessionActive && !viewModel.livenessPassed {
                stepDots
            }

            HStack(alignment: .top, spacing: 10) {
                if viewModel.isSessionActive {
                    statusIcon
                        .font(.title2)
                        .foregroundStyle(statusAccent)
                        .frame(width: 32)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(viewModel.isSessionActive ? .headline : .subheadline.weight(.semibold))

                    if viewModel.isSessionActive {
                        Text(viewModel.primaryInstruction)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let secondary = viewModel.secondaryInstruction {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !viewModel.isSessionActive {
                        readyScanStepsList
                    }

                    if viewModel.showsRecognitionDetails, let name = viewModel.lastMatchName {
                        Text(name)
                            .font(.title3.weight(.bold))
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(viewModel.isSessionActive ? 16 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(statusAccent.opacity(0.25), lineWidth: 1)
        }
    }

    private var readyScanStepsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.readyScanCompactLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !viewModel.readyScanExtras.isEmpty {
                Text(viewModel.readyScanExtras.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(1...viewModel.livenessTotalSteps, id: \.self) { step in
                Capsule()
                    .fill(stepFill(for: step))
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.livenessStepNumber)
    }

    private func stepFill(for step: Int) -> Color {
        if step < viewModel.livenessStepNumber {
            return .green
        }
        if step == viewModel.livenessStepNumber {
            return viewModel.guideConditionMet ? .green : .teal
        }
        return Color.secondary.opacity(0.25)
    }

    private var statusTitle: String {
        if !viewModel.isSessionActive { return "Ready" }
        if viewModel.successFlash { return "Recorded" }
        if !viewModel.livenessPassed {
            let step = viewModel.livenessStepNumber
            if viewModel.isAwaitingDepthConfirm { return "Step \(step) — 3D check" }
            switch viewModel.livenessChallenge {
            case .blink: return "Step \(step) — Blink"
            case .turnLeft: return "Step \(step) — Look left"
            case .turnRight: return "Step \(step) — Look right"
            case .nodUp: return "Step \(step) — Look up"
            case .nodDown: return "Step \(step) — Look down"
            case .moveCloser: return "Step \(step) — Move closer"
            case .confirm3D: return "Step \(step) — 3D check"
            }
        }
        switch viewModel.recognitionState {
        case .verifying: return "Verifying"
        case .recognized: return "Matched"
        case .alreadyRecorded: return "Already recorded"
        case .wrongJobSite: return "Invalid — wrong site"
        case .unknownPerson:
            return "Not recognized"
        case .poorQuality:
            return "Try again"
        case .noFace: return "Find your face"
        case .idle, .liveness: return "Matching"
        }
    }

    private var statusIcon: Image {
        if !viewModel.isSessionActive {
            return Image(systemName: "faceid")
        }
        if viewModel.successFlash {
            return Image(systemName: "checkmark.circle.fill")
        }
        if !viewModel.livenessPassed {
            if viewModel.isAwaitingDepthConfirm {
                return Image(systemName: LivenessChallenge.confirm3D.systemImage)
            }
            return Image(systemName: viewModel.livenessChallenge.systemImage)
        }
        switch viewModel.recognitionState {
        case .verifying:
            return Image(systemName: "ellipsis.circle")
        case .recognized:
            return Image(systemName: "checkmark.circle.fill")
        case .alreadyRecorded:
            return Image(systemName: "exclamationmark.circle.fill")
        case .wrongJobSite:
            return Image(systemName: "mappin.slash.circle.fill")
        case .unknownPerson:
            return Image(systemName: "person.slash")
        case .poorQuality:
            return Image(systemName: "exclamationmark.triangle")
        default:
            return Image(systemName: "viewfinder")
        }
    }

    private var statusAccent: Color {
        if viewModel.successFlash { return .green }
        if !viewModel.isSessionActive { return .teal }
        if !viewModel.livenessPassed {
            return viewModel.guideConditionMet ? .green : .teal
        }
        switch viewModel.recognitionState {
        case .recognized: return .green
        case .alreadyRecorded: return .orange
        case .wrongJobSite: return .red
        case .unknownPerson, .poorQuality: return .orange
        case .verifying: return .yellow
        default: return .teal
        }
    }

    // MARK: - Actions

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
                .disabled(viewModel.isSessionActive || viewModel.isProcessing || viewModel.isScannerLocationBlocked)

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
                .disabled(viewModel.isSessionActive || viewModel.isProcessing || viewModel.isScannerLocationBlocked)
            }

            if viewModel.isScannerLocationBlocked && !viewModel.isSessionActive {
                Button {
                    Task { await viewModel.refreshScannerLocationGate() }
                } label: {
                    Label("Recheck Location", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.isSessionActive {
                Button("Cancel Scan") {
                    viewModel.endSession(status: "Choose Time In or Time Out to begin.")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 0)
    }

    // MARK: - Helpers

    private var borderColor: Color {
        if viewModel.successFlash { return .green }
        guard viewModel.isSessionActive else { return .white.opacity(0.28) }
        if viewModel.guideConditionMet { return .green }
        switch viewModel.recognitionState {
        case .noFace: return .white.opacity(0.35)
        case .liveness: return .teal
        case .unknownPerson, .poorQuality: return .orange.opacity(0.85)
        case .verifying: return .yellow.opacity(0.9)
        case .recognized: return .green
        case .alreadyRecorded: return .orange
        case .wrongJobSite: return .red.opacity(0.9)
        case .idle: return viewModel.faceDetected ? .teal : .white.opacity(0.35)
        }
    }

    /// Stable animation key for border color changes.
    private var borderColorDescription: String {
        "\(viewModel.recognitionState)-\(viewModel.guideConditionMet)-\(viewModel.successFlash)"
    }

    private func lockCameraSizeIfNeeded(width: CGFloat, height: CGFloat) {
        guard width > 0, height > 0, lockedCameraSize == nil else { return }
        lockedCameraSize = CGSize(width: width, height: height)
    }

    private var locationBlockedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 44))
            Text("Off Site")
                .font(.title3.weight(.semibold))
            Text(viewModel.scannerLocationMessage ?? "Move to the job site or update location in More → Job Sites.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private var supervisorPINSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Supervisor PIN required")
                    .font(.title3.weight(.semibold))
                Text("A supervisor must authorize this punch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SecureField("PIN", text: $viewModel.supervisorPINEntry)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                if let error = viewModel.supervisorPINError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Authorize") {
                    viewModel.submitSupervisorPIN()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.supervisorPINEntry.count < 4)
                Spacer()
            }
            .padding()
            .navigationTitle("Authorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelSupervisorPIN() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
