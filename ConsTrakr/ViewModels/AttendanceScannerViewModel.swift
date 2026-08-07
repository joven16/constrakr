//
//  AttendanceScannerViewModel.swift
//  ConsTrakr
//
//  FIX: Hard-reset scanner state, skip warmup frames, require multi-frame consensus,
//  and never keep a previous employee name across scans.
//

import AVFoundation
import CoreVideo
import Foundation
import SwiftData

enum ScannerRecognitionState {
    case idle
    case noFace
    case liveness
    case unknownPerson
    case poorQuality
    case verifying
    case recognized
    case alreadyRecorded
    case wrongJobSite
}

@MainActor
@Observable
final class AttendanceScannerViewModel {
    var checkType: CheckType = .checkIn

    private(set) var statusMessage = "Choose Time In or Time Out to begin."
    private(set) var recognitionState: ScannerRecognitionState = .idle
    private(set) var faceDetected = false
    private(set) var lastMatchName: String?
    private(set) var lastMatchConfidence: Float?
    private(set) var isProcessing = false
    private(set) var successFlash = false
    private(set) var errorMessage: String?
    private(set) var cameraError: String?
    /// Scanning only runs after the user confirms Time In or Time Out.
    private(set) var isSessionActive = false
    private(set) var livenessChallenge: LivenessChallenge = .blink
    private(set) var livenessPassed = false
    private(set) var livenessHint = "Center your face"
    private(set) var livenessStepLabel = "Step 1 of 4"
    /// Stored (not computed) so SwiftUI/@Observable reliably refreshes step UI.
    private(set) var livenessStepNumber = 1
    private(set) var livenessTotalSteps = 4
    /// After turn/nod: show center cue instead of side arrow.
    private(set) var livenessNeedsLookStraight = false
    /// After blink/turn/closer: require consecutive real 3D depth frames.
    private(set) var isAwaitingDepthConfirm = false
    private var depthConfirmStreak = 0
    private let depthConfirmNeeded = 10
    /// Calm instruction — only changes when the step changes, not every frame.
    private var stableInstruction = "Blink both eyes slowly"
    /// Challenge shown on the camera overlay (includes 3D confirm step).
    var overlayChallenge: LivenessChallenge? {
        guard isSessionActive, !livenessPassed else { return nil }
        if isAwaitingDepthConfirm { return .confirm3D }
        return livenessChallenge
    }
    /// Outline turns green while the live-check gesture is currently satisfied.
    private(set) var guideConditionMet = false
    var pendingConfirmType: CheckType?
    /// After Confirm, show supervisor PIN sheet when enabled.
    private(set) var isAwaitingSupervisorPIN = false
    var supervisorPINEntry = ""
    private(set) var supervisorPINError: String?
    private(set) var siteGateMessage: String?
    /// When geofence is on, blocks the scanner UI until the phone is at the default job site.
    private(set) var isScannerLocationBlocked = false
    private(set) var scannerLocationMessage: String?
    /// Default job site from Settings, shown on the scanner frame.
    private(set) var operatingSiteLabel = JobSiteStore.currentOperatingSiteLabel()
    /// Blocks alert-dismiss `cancelConfirm` from wiping an in-flight Time In/Out start.
    private var isStartingAuthorizedSession = false

    private(set) var readyScanPresetLabel = FaceScanSettings.scannerPresetLabel()
    private(set) var readyScanStepLabels: [String] = FaceScanSettings.scannerReadyStepNames(include3D: false)
    private(set) var readyScanCompactLine = FaceScanSettings.scannerPresetLabel()
    private(set) var readyScanExtras: [String] = []
    /// True when TrueDepth maps are available (shown on Ready steps).
    private(set) var scannerDepthAvailable = false

    var showsRecognitionDetails: Bool {
        switch recognitionState {
        case .recognized, .alreadyRecorded, .wrongJobSite:
            return lastMatchName != nil && lastMatchConfidence != nil
        default:
            return false
        }
    }

    /// 0…1 progress through the live-check steps (for the step dots).
    var livenessProgress: Double {
        guard isSessionActive, !livenessPassed else {
            return livenessPassed ? 1 : 0
        }
        let total = max(livenessTotalSteps, 1)
        if isAwaitingDepthConfirm {
            let base = Double(total - 1) / Double(total)
            let frac = Double(depthConfirmStreak) / Double(max(depthConfirmNeeded, 1))
            return min(0.99, base + frac / Double(total))
        }
        return Double(livenessStepNumber - 1) / Double(total)
    }

    /// Single calm line for the camera caption + status card.
    var primaryInstruction: String {
        if let cameraError { return cameraError }
        if !isSessionActive {
            return "Tap Time In or Time Out to start"
        }
        if !livenessPassed {
            if recognitionState == .noFace {
                return isAwaitingDepthConfirm
                    ? "Keep your face in the outline"
                    : "Center your face in the outline"
            }
            return stableInstruction
        }
        switch recognitionState {
        case .verifying:
            return statusMessage
        case .recognized, .alreadyRecorded:
            return statusMessage
        case .wrongJobSite:
            return statusMessage
        case .unknownPerson:
            return statusMessage.isEmpty ? "Face not recognized" : statusMessage
        case .poorQuality:
            return stableInstruction
        case .noFace:
            return "Center your face in the outline"
        default:
            return faceDetected ? "Matching face…" : "Center your face in the outline"
        }
    }

    var secondaryInstruction: String? {
        if !isSessionActive {
            return nil
        }
        if !livenessPassed {
            return livenessStepLabel
        }
        if recognitionState == .recognized || recognitionState == .alreadyRecorded,
           let confidence = lastMatchConfidence {
            return String(format: "Confidence %.0f%%", max(0, min(confidence, 1)) * 100)
        }
        if livenessPassed && (recognitionState == .idle || recognitionState == .verifying) {
            return "Hold still while we match"
        }
        return nil
    }

    private func setStableInstruction(_ text: String) {
        guard stableInstruction != text else { return }
        stableInstruction = text
    }

    private func syncStableInstructionForLiveness() {
        if isAwaitingDepthConfirm {
            setStableInstruction("Hold still — 3D check")
            return
        }
        if livenessChecker.needsLookStraight {
            setStableInstruction("Look straight at the camera")
            return
        }
        setStableInstruction(livenessChallenge.instruction)
    }

    let cameraManager = CameraManager()

    private let pipeline = FaceRecognitionPipeline()
    private let detectionService = FaceDetectionService()
    private var livenessChecker = LivenessChecker()
    private let depthMotionValidator = DepthMotionValidator()
    private let spoofTracker = PresentationSpoofDetector.Tracker()
    private let antiSpoofTracker = AntiSpoofTracker()
    /// True once we received a usable depth map this session.
    private var sawValidDepthThisSession = false
    /// If TrueDepth never delivers maps, fall back so the scanner is not bricked.
    /// Face crop from the consensus frame saved with the punch for audit.
    private var pendingPunchJPEG: Data?
    private var attendanceService: AttendanceService?
    private var employeeService: EmployeeService?
    private var syncQueue: SyncQueue?
    private var employees: [Employee] = []
    private var lastScanDate: Date?
    private var isHandlingFrame = false
    private var recordedKeysToday: Set<String> = []
    private let siteLocationGate = SiteLocationGate()
    private var locationMonitorTask: Task<Void, Never>?
    /// Held while PIN / geofence gates run after Confirm.
    private var pendingSessionType: CheckType?

    /// Discard frames after camera start / after a completed scan (timing / stale buffer).
    private var warmupFramesRemaining = 0
    /// Consecutive frames that agreed on the same employee above threshold.
    private var consensusEmployeeId: UUID?
    private var consensusCount = 0
    private var consensusBestScore: Float = 0
    private var consensusName: String?
    private var unknownPersonCancelTask: Task<Void, Never>?

    func configure(context: ModelContext, syncQueue: SyncQueue) {
        attendanceService = AttendanceService(context: context)
        employeeService = EmployeeService(context: context)
        self.syncQueue = syncQueue
        endSession(status: "Choose Time In or Time Out to begin.")
        reloadEmployees()
        refreshScannerReadySteps()
    }

    /// Reloads Ready-screen steps from Settings → Face Scanner (call on scanner open).
    func refreshScannerReadySteps() {
        operatingSiteLabel = JobSiteStore.currentOperatingSiteLabel()
        readyScanPresetLabel = FaceScanSettings.scannerPresetLabel()
        readyScanStepLabels = FaceScanSettings.scannerReadyStepNames(include3D: scannerDepthAvailable)
        readyScanCompactLine = Self.makeReadyCompactLine(
            preset: readyScanPresetLabel,
            steps: readyScanStepLabels
        )
        var extras: [String] = []
        if SupervisorPINSettings.isRequired { extras.append("Supervisor PIN required") }
        if SiteGeofenceSettings.isRequired { extras.append("On-site GPS required") }
        readyScanExtras = extras
    }

    private static func makeReadyCompactLine(preset: String, steps: [String]) -> String {
        guard !steps.isEmpty else { return preset }
        return "\(preset): \(steps.joined(separator: " → "))"
    }

    func requestConfirm(_ type: CheckType) {
        guard !isProcessing else { return }
        if isScannerLocationBlocked {
            siteGateMessage = scannerLocationMessage
                ?? "You must be at the job site to punch. Update location in Settings → Job Sites."
            return
        }
        pendingConfirmType = type
    }

    func cancelConfirm() {
        // SwiftUI sets alert isPresented=false after Confirm, which would otherwise
        // wipe pendingSessionType before beginSession runs.
        if isStartingAuthorizedSession { return }

        pendingConfirmType = nil
        pendingSessionType = nil
        isAwaitingSupervisorPIN = false
        supervisorPINEntry = ""
        supervisorPINError = nil
        siteGateMessage = nil
    }

    func confirmPendingType() {
        guard let type = pendingConfirmType else { return }
        isStartingAuthorizedSession = true
        pendingConfirmType = nil
        pendingSessionType = type

        if SupervisorPINSettings.isRequired {
            isAwaitingSupervisorPIN = true
            supervisorPINEntry = ""
            supervisorPINError = nil
            return
        }

        // Most common path: no GPS gate — start immediately (avoids alert-dismiss races).
        if !SiteGeofenceSettings.isRequired {
            pendingSessionType = nil
            beginSession(type: type)
            isStartingAuthorizedSession = false
            return
        }

        Task { await startSessionAfterGuards() }
    }

    func submitSupervisorPIN() {
        guard let type = pendingSessionType else { return }
        if SupervisorPINSettings.verify(supervisorPINEntry) {
            isAwaitingSupervisorPIN = false
            supervisorPINEntry = ""
            supervisorPINError = nil
            isStartingAuthorizedSession = true
            pendingSessionType = type
            Task { await startSessionAfterGuards() }
        } else {
            supervisorPINError = "Incorrect supervisor PIN"
            supervisorPINEntry = ""
        }
    }

    func cancelSupervisorPIN() {
        isStartingAuthorizedSession = false
        isAwaitingSupervisorPIN = false
        pendingSessionType = nil
        supervisorPINEntry = ""
        supervisorPINError = nil
        pendingConfirmType = nil
        statusMessage = "Choose Time In or Time Out to begin."
    }

    func dismissSiteGateMessage() {
        siteGateMessage = nil
    }

    func refreshScannerLocationGate() async {
        guard SiteGeofenceSettings.isRequired, let site = JobSiteStore.defaultSite else {
            isScannerLocationBlocked = false
            scannerLocationMessage = nil
            refreshScannerReadySteps()
            return
        }

        let result = await siteLocationGate.isInside(site: site)
        switch result {
        case .success(let inside):
            isScannerLocationBlocked = !inside
            scannerLocationMessage = inside
                ? nil
                : "You are outside \(site.displayTitle). Move to the site or update location in Settings → Job Sites."
        case .failure(let error):
            isScannerLocationBlocked = true
            scannerLocationMessage = error.localizedDescription
        }
        refreshScannerReadySteps()
    }

    private func startLocationMonitoring() {
        locationMonitorTask?.cancel()
        guard SiteGeofenceSettings.isRequired else {
            isScannerLocationBlocked = false
            scannerLocationMessage = nil
            return
        }
        locationMonitorTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshScannerLocationGate()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func stopLocationMonitoring() {
        locationMonitorTask?.cancel()
        locationMonitorTask = nil
    }

    private func startSessionAfterGuards() async {
        guard let type = pendingSessionType else {
            isStartingAuthorizedSession = false
            return
        }
        siteGateMessage = nil
        statusMessage = SiteGeofenceSettings.isRequired
            ? "Checking job-site GPS…"
            : "Starting live check…"
        do {
            try await siteLocationGate.verifyInsideSiteIfRequired()
        } catch {
            isStartingAuthorizedSession = false
            pendingSessionType = nil
            siteGateMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            return
        }
        pendingSessionType = nil
        beginSession(type: type)
        isStartingAuthorizedSession = false
    }

    func beginSession(type: CheckType) {
        cancelUnknownPersonAutoCancel()
        checkType = type
        isSessionActive = true
        livenessChecker.resetForScanner()
        depthMotionValidator.reset()
        spoofTracker.reset()
        antiSpoofTracker.reset()
        sawValidDepthThisSession = false
        isAwaitingDepthConfirm = false
        depthConfirmStreak = 0
        pendingPunchJPEG = nil
        lastScanDate = nil
        livenessChallenge = livenessChecker.challenge
        livenessPassed = false
        livenessHint = livenessChecker.progressHint
        syncLivenessStepUI()
        syncStableInstructionForLiveness()
        guideConditionMet = false
        hardResetScanner(status: "Follow the on-screen steps")
        recognitionState = .liveness
        statusMessage = stableInstruction
        warmupFramesRemaining = AppConstants.scannerWarmupFrames
    }

    private func syncLivenessStepUI() {
        let gestureSteps = livenessChecker.totalSteps
        // Gestures + final 3D depth confirmation.
        livenessTotalSteps = gestureSteps + 1
        if isAwaitingDepthConfirm {
            livenessStepNumber = livenessTotalSteps
            livenessStepLabel = "Step \(livenessTotalSteps) of \(livenessTotalSteps)"
            livenessNeedsLookStraight = false
            livenessChallenge = .confirm3D
        } else {
            livenessStepLabel = livenessChecker.stepLabel
            livenessStepNumber = livenessChecker.currentStepNumber
            livenessNeedsLookStraight = livenessChecker.needsLookStraight
        }
    }

    func endSession(status: String) {
        cancelUnknownPersonAutoCancel()
        isSessionActive = false
        isStartingAuthorizedSession = false
        pendingConfirmType = nil
        pendingSessionType = nil
        isAwaitingSupervisorPIN = false
        livenessPassed = false
        guideConditionMet = false
        hardResetScanner(status: status)
    }

    /// Clears in-memory "already timed in/out" state after attendance history is wiped.
    func handleAttendanceHistoryCleared() {
        recordedKeysToday.removeAll()
        lastScanDate = nil
        endSession(status: "Choose Time In or Time Out to begin.")
    }

    func updateCheckType(_ type: CheckType) {
        beginSession(type: type)
    }

    func reloadEmployees() {
        let expectedDim = FaceEmbedding.expectedDimension
        employees = ((try? employeeService?.allEmployees()) ?? []).filter { employee in
            // Ignore empty or legacy wrong-dimension embeddings (must re-enroll after AdaFace).
            employee.isEnrolled
                && employee.faceEmbeddings.contains { $0.values.count == expectedDim }
        }
    }

    func startCamera() async {
        endSession(status: "Starting camera…")
        reloadEmployees()
        do {
            try await cameraManager.requestAccessAndConfigure()
            cameraManager.onFrame = { [weak self] buffer, depth in
                Task { @MainActor in
                    self?.handleFrame(buffer, depthData: depth)
                }
            }
            cameraManager.start()
            cameraError = nil
            scannerDepthAvailable = cameraManager.isDepthAvailable
            refreshScannerReadySteps()
            statusMessage = "Choose Time In or Time Out to begin."
            recognitionState = .idle
            await refreshScannerLocationGate()
            startLocationMonitoring()
        } catch {
            cameraError = error.localizedDescription
        }
    }

    func stopCamera() {
        stopLocationMonitoring()
        cameraManager.onFrame = nil
        cameraManager.stop()
        endSession(status: "Scanner stopped")
    }

    /// Clears previous recognition, consensus, and timing before a new attempt.
    func hardResetScanner(status: String) {
        cancelUnknownPersonAutoCancel()
        lastMatchName = nil
        lastMatchConfidence = nil
        faceDetected = false
        successFlash = false
        recognitionState = .idle
        statusMessage = status
        consensusEmployeeId = nil
        consensusCount = 0
        consensusBestScore = 0
        consensusName = nil
        warmupFramesRemaining = AppConstants.scannerWarmupFrames
        isHandlingFrame = false
        // Keep lastScanDate only for cooldown; do not reuse prior match identity.
    }

    private func pauseLiveCheck(message: String) {
        guideConditionMet = false
        resetConsensus()
        recognitionState = .liveness
        setStableInstruction(message)
        statusMessage = message
    }

    private func rejectPresentationAttack(_ message: String) {
        livenessChecker.resetForScanner()
        isAwaitingDepthConfirm = false
        depthConfirmStreak = 0
        depthMotionValidator.reset()
        spoofTracker.reset()
        antiSpoofTracker.reset()
        livenessPassed = false
        syncLivenessStepUI()
        syncStableInstructionForLiveness()
        setStableInstruction(message)
        statusMessage = message
        guideConditionMet = false
        recognitionState = .liveness
        resetConsensus()
    }

    private func finishLivenessAndBeginMatching() {
        isAwaitingDepthConfirm = false
        livenessPassed = true
        livenessStepNumber = livenessTotalSteps
        livenessStepLabel = "Step \(livenessTotalSteps) of \(livenessTotalSteps)"
        setStableInstruction("Matching face…")
        statusMessage = stableInstruction
        syncLivenessStepUI()
        resetConsensus()
    }

    /// After 2D gestures (blink / turns / close-up) complete.
    private func completeGesturePhase() {
        let requiresMoveCloserDepth = livenessChecker.steps.contains(.moveCloser)
        if requiresMoveCloserDepth,
           cameraManager.isDepthAvailable,
           !depthMotionValidator.passedMoveCloserDepthCheck() {
            rejectPresentationAttack(
                "Screen replay detected — physically move closer, not a video zoom."
            )
            return
        }

        if cameraManager.isDepthAvailable {
            isAwaitingDepthConfirm = true
            depthConfirmStreak = 0
            depthMotionValidator.resetConfirmSamples()
            setStableInstruction("Hold still — 3D check")
            statusMessage = stableInstruction
            syncLivenessStepUI()
            guideConditionMet = true
        } else {
            finishLivenessAndBeginMatching()
        }
    }

    /// RGB replay cues. Used during liveness, not identity matching.
    private func looksLikeScreenReplay(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> Bool {
        spoofTracker.observe(pixelBuffer: pixelBuffer, faceBox: faceBox, rejectThreshold: 0.58)
    }

    /// MiniFASNet Core ML — catches photo / screen / video replay.
    private func looksLikeAISpoof(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> Bool {
        guard CoreMLAntiSpoof.shared.isReady else { return false }
        guard let verdict = try? CoreMLAntiSpoof.shared.classify(
            pixelBuffer: pixelBuffer,
            boundingBox: faceBox
        ) else { return false }
        return antiSpoofTracker.observe(
            liveScore: verdict.liveScore,
            liveThreshold: CoreMLAntiSpoof.liveThreshold
        )
    }

    private func clearRecognitionIdentity() {
        lastMatchName = nil
        lastMatchConfidence = nil
    }

    private func resetConsensus() {
        consensusEmployeeId = nil
        consensusCount = 0
        consensusBestScore = 0
        consensusName = nil
        // Keep pendingPunchJPEG across consensus frames; cleared on session restart / after save.
    }

    /// Depth gate — returns whether this frame counts. Never restarts the whole scan.
    private func depthAllowsFrame(
        depthData: AVDepthData?,
        faceBox: CGRect,
        strict: Bool = false
    ) -> Bool {
        // Non-TrueDepth devices cannot run 3D anti-spoof — gestures only.
        guard cameraManager.isDepthAvailable else { return true }
        guard let depthData else { return false }
        let verdict = DepthFlatnessDetector.evaluate(
            depthData: depthData,
            faceBox: faceBox,
            strict: strict
        )
        return !verdict.isFlat
    }

    private func recordKey(employeeId: UUID, checkType: CheckType) -> String {
        "\(employeeId.uuidString)-\(checkType.rawValue)"
    }

    private func handleFrame(_ pixelBuffer: CVPixelBuffer, depthData: AVDepthData?) {
        guard isSessionActive else { return }
        guard !isHandlingFrame, !isProcessing else { return }

        // Cooldown after a completed scan: clear UI, do not keep previous employee on screen.
        if let last = lastScanDate, Date().timeIntervalSince(last) < AppConstants.scannerCooldown {
            if recognitionState == .recognized || recognitionState == .alreadyRecorded {
                // Keep the completed-scan message briefly, but drop identity after cooldown starts.
            } else if lastMatchName != nil {
                clearRecognitionIdentity()
            }
            return
        }

        if warmupFramesRemaining > 0 {
            warmupFramesRemaining -= 1
            clearRecognitionIdentity()
            recognitionState = .idle
            statusMessage = "Calibrating camera…"
            resetConsensus()
            return
        }

        isHandlingFrame = true
        defer { isHandlingFrame = false }

        // Always clear previous identity before scoring this frame.
        clearRecognitionIdentity()

        let mirrored = cameraManager.position == .front

        do {
            // Copy once so liveness + matching never read a recycled camera buffer.
            let frame = try FaceImagePreprocessor.copyPixelBuffer(pixelBuffer)
            let face = try detectionService.primaryFace(in: frame, mirrored: mirrored)
            faceDetected = face != nil

            // 1) Liveness must pass before any identity matching.
            if !livenessPassed {
                if cameraManager.position != .front {
                    pauseLiveCheck(message: "Use the front camera")
                    return
                }

                guard let face else {
                    depthConfirmStreak = 0
                    if !isAwaitingDepthConfirm {
                        _ = livenessChecker.update(
                            hasFace: false,
                            yaw: 0,
                            pitch: 0,
                            leftEyeEAR: nil,
                            rightEyeEAR: nil,
                            faceArea: 0,
                            mirrored: mirrored
                        )
                        livenessChallenge = livenessChecker.challenge
                        syncLivenessStepUI()
                    }
                    guideConditionMet = false
                    recognitionState = .noFace
                    resetConsensus()
                    return
                }

                if looksLikeScreenReplay(pixelBuffer: frame, faceBox: face.boundingBox) {
                    rejectPresentationAttack(
                        spoofTracker.rejectReason ?? "Screen or video replay detected. Use a live person."
                    )
                    return
                }

                if looksLikeAISpoof(pixelBuffer: frame, faceBox: face.boundingBox) {
                    rejectPresentationAttack(
                        "AI detected a screen or photo replay. Use a live person."
                    )
                    return
                }

                // 3D confirm: strict TrueDepth + depth stability — blocks flat screens and scrubbed video.
                if isAwaitingDepthConfirm {
                    if !cameraManager.isDepthAvailable {
                        finishLivenessAndBeginMatching()
                        resetConsensus()
                        return
                    }
                    if let depthData {
                        depthMotionValidator.observeDepthConfirm(
                            depthData: depthData,
                            faceBox: face.boundingBox
                        )
                    }
                    if let depthData,
                       depthAllowsFrame(
                           depthData: depthData,
                           faceBox: face.boundingBox,
                           strict: true
                       ),
                       depthMotionValidator.depthConfirmIsStable() {
                        depthConfirmStreak += 1
                        sawValidDepthThisSession = true
                        guideConditionMet = true
                        recognitionState = .liveness
                        if depthConfirmStreak >= depthConfirmNeeded {
                            finishLivenessAndBeginMatching()
                        }
                    } else {
                        depthConfirmStreak = max(0, depthConfirmStreak - 1)
                        guideConditionMet = false
                        recognitionState = .liveness
                    }
                    resetConsensus()
                    return
                }

                // Gestures: blink → turn → move closer (2D motion + stable instructions).
                let faceArea = face.boundingBox.width * face.boundingBox.height
                if livenessChallenge == .moveCloser, let depthData {
                    depthMotionValidator.observeMoveCloser(
                        faceArea: faceArea,
                        depthData: depthData,
                        faceBox: face.boundingBox
                    )
                }
                let passed = livenessChecker.update(
                    hasFace: true,
                    yaw: face.yaw,
                    pitch: face.pitch,
                    leftEyeEAR: face.leftEyeEAR,
                    rightEyeEAR: face.rightEyeEAR,
                    faceArea: faceArea,
                    mirrored: mirrored
                )
                livenessChallenge = livenessChecker.challenge
                syncLivenessStepUI()
                syncStableInstructionForLiveness()
                guideConditionMet = livenessChecker.isConditionMet
                recognitionState = .liveness
                statusMessage = stableInstruction

                if passed {
                    completeGesturePhase()
                }
                resetConsensus()
                return
            }

            // 2) Identity matching — liveness + 3D already passed.
            guard let face else {
                faceDetected = false
                guideConditionMet = false
                recognitionState = .noFace
                setStableInstruction("Center your face in the outline")
                resetConsensus()
                return
            }

            if let jpeg = AttendancePhotoStore.encodeFaceJPEG(
                from: frame,
                boundingBox: face.boundingBox
            ) {
                pendingPunchJPEG = jpeg
            }

            guideConditionMet = true
            reloadEmployees()
            let match = try pipeline.process(pixelBuffer: frame, employees: employees, mirrored: mirrored)
            faceDetected = true
            handleConsensusMatch(match)
        } catch FaceRecognitionPipeline.PipelineError.noFaceDetected {
            resetConsensus()
            faceDetected = false
            guideConditionMet = false
            recognitionState = .noFace
            setStableInstruction("Center your face in the outline")
        } catch FaceRecognitionPipeline.PipelineError.unknownPerson(let bestSimilarity) {
            if consensusCount > 0 {
                cancelUnknownPersonAutoCancel()
                resetConsensus()
                recognitionState = .verifying
                statusMessage = "Hold still while we match"
                return
            }
            resetConsensus()
            faceDetected = true
            guideConditionMet = true
            recognitionState = .unknownPerson
            if bestSimilarity > 0 {
                statusMessage = String(
                    format: "Not recognized (best %.0f%% — need %.0f%%)",
                    bestSimilarity * 100,
                    MatchThresholdSettings.current * 100
                )
            } else if employees.isEmpty {
                statusMessage = "No enrolled faces — register first"
            } else {
                statusMessage = "Face not recognized"
            }
            scheduleUnknownPersonAutoCancel()
        } catch FaceRecognitionPipeline.PipelineError.poorQuality {
            if consensusCount > 0 {
                cancelUnknownPersonAutoCancel()
                resetConsensus()
                recognitionState = .verifying
                statusMessage = "Hold still while we match"
                return
            }
            resetConsensus()
            faceDetected = true
            guideConditionMet = true
            recognitionState = .unknownPerson
            statusMessage = "Try better lighting and look at the camera"
        } catch {
            if consensusCount > 0 {
                cancelUnknownPersonAutoCancel()
                resetConsensus()
                recognitionState = .verifying
                statusMessage = "Hold still while we match"
                return
            }
            resetConsensus()
            guideConditionMet = false
            recognitionState = .unknownPerson
            statusMessage = "Face not recognized"
            scheduleUnknownPersonAutoCancel()
        }
    }

    private func scheduleUnknownPersonAutoCancel() {
        guard unknownPersonCancelTask == nil else { return }
        unknownPersonCancelTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(AppConstants.unknownPersonAutoCancelDelay))
            guard !Task.isCancelled, isSessionActive, recognitionState == .unknownPerson else {
                unknownPersonCancelTask = nil
                return
            }
            unknownPersonCancelTask = nil
            endSession(status: "Choose Time In or Time Out to begin.")
            lastScanDate = Date()
        }
    }

    private func cancelUnknownPersonAutoCancel() {
        unknownPersonCancelTask?.cancel()
        unknownPersonCancelTask = nil
    }

    /// Require several consecutive agreeing frames before saving attendance.
    private func handleConsensusMatch(_ match: FaceMatchResult) {
        cancelUnknownPersonAutoCancel()
        if consensusEmployeeId == match.employeeId {
            consensusCount += 1
            consensusBestScore = max(consensusBestScore, match.similarity)
        } else {
            consensusEmployeeId = match.employeeId
            consensusCount = 1
            consensusBestScore = match.similarity
            consensusName = match.employeeName
        }

        if consensusCount < AppConstants.scannerConsensusFrames {
            recognitionState = .verifying
            statusMessage = "Verifying \(match.employeeName)… (\(consensusCount)/\(AppConstants.scannerConsensusFrames))"
            // Do not show final confidence until consensus completes.
            clearRecognitionIdentity()
            return
        }

        // Consensus reached — lock immediately so the next frame cannot flash "not recognized".
        lastMatchName = match.employeeName
        lastMatchConfidence = consensusBestScore
        recognitionState = .verifying
        statusMessage = "Recording \(match.employeeName)…"
        isProcessing = true
        let confirmed = FaceMatchResult(
            employeeId: match.employeeId,
            employeeCode: match.employeeCode,
            employeeName: match.employeeName,
            similarity: consensusBestScore,
            matchedPose: match.matchedPose
        )
        resetConsensus()
        Task { await recordMatch(confirmed) }
    }

    private func recordMatch(_ match: FaceMatchResult) async {
        guard let attendanceService else {
            isProcessing = false
            endSession(status: "Choose Time In or Time Out to begin.")
            return
        }
        defer { isProcessing = false }

        let key = recordKey(employeeId: match.employeeId, checkType: checkType)

        do {
            try await ClockIntegrityGuard.shared.verifyBeforePunch()
            try await verifySiteBeforePunch(employeeId: match.employeeId)

            if let existing = try attendanceService.todaysRecord(
                employeeId: match.employeeId,
                checkType: checkType
            ) {
                recordedKeysToday.insert(key)
                await presentAlreadyRecorded(match: match, at: existing.timestamp)
                return
            }

            if recordedKeysToday.contains(key) {
                await presentAlreadyRecorded(match: match, at: nil)
                return
            }

            let punchTime = ClockIntegrityGuard.shared.preferredPunchTimestamp()
            let attendance = try attendanceService.record(
                employeeId: match.employeeId,
                checkType: checkType,
                confidence: Double(match.similarity),
                notes: "Matched pose: \(match.matchedPose.rawValue)",
                punchPhotoJPEG: pendingPunchJPEG,
                timestamp: punchTime
            )
            ClockIntegrityGuard.shared.recordSuccessfulPunch()
            pendingPunchJPEG = nil
            recordedKeysToday.insert(key)
            lastMatchName = match.employeeName
            lastMatchConfidence = match.similarity
            lastScanDate = attendance.timestamp
            successFlash = true
            recognitionState = .recognized
            let when = attendance.timestamp.attendanceDisplay
            let message = "\(checkType.displayName): \(match.employeeName) · \(when)"
            statusMessage = message
            syncQueue?.refreshPendingCount()

            if NetworkMonitor.shared.isConnected {
                await syncQueue?.syncNow()
            }

            try? await Task.sleep(for: .seconds(2.5))
            successFlash = false
            endSession(status: "Choose Time In or Time Out to begin.")
            lastScanDate = Date()
        } catch let error as ClockIntegrityError {
            await presentClockIntegrityError(match: match, error: error)
            return
        } catch let error as SiteLocationGate.GateError {
            await presentInvalidSitePunch(match: match, error: error)
            return
        } catch AttendanceService.ServiceError.alreadyRecordedToday {
            let existing = try? attendanceService.todaysRecord(
                employeeId: match.employeeId,
                checkType: checkType
            )
            recordedKeysToday.insert(key)
            await presentAlreadyRecorded(match: match, at: existing?.timestamp)
        } catch {
            errorMessage = error.localizedDescription
            endSession(status: "Choose Time In or Time Out to begin.")
            lastScanDate = Date()
        }
    }

    private func verifySiteBeforePunch(employeeId: UUID) async throws {
        if let employee = try employeeService?.employee(id: employeeId) {
            await employeeService?.refreshProfileFromServer(employee)
            try await siteLocationGate.verifyAttendanceSite(for: employee)
            return
        }
        if SiteGeofenceSettings.isRequired, let defaultSite = JobSiteStore.defaultSite {
            try await siteLocationGate.verifyInside(site: defaultSite)
        }
    }

    private func presentClockIntegrityError(match: FaceMatchResult, error: ClockIntegrityError) async {
        lastMatchName = match.employeeName
        lastMatchConfidence = match.similarity
        lastScanDate = Date()
        successFlash = false
        pendingPunchJPEG = nil
        recognitionState = .wrongJobSite
        let message = error.localizedDescription
        statusMessage = message
        siteGateMessage = message
        errorMessage = message

        try? await Task.sleep(for: .seconds(3.0))
        siteGateMessage = nil
        endSession(status: "Choose Time In or Time Out to begin.")
        lastScanDate = Date()
    }

    private func presentInvalidSitePunch(match: FaceMatchResult, error: Error) async {
        lastMatchName = match.employeeName
        lastMatchConfidence = match.similarity
        lastScanDate = Date()
        successFlash = false
        pendingPunchJPEG = nil
        recognitionState = .wrongJobSite
        let message = error.localizedDescription
        statusMessage = message
        siteGateMessage = message
        errorMessage = message

        try? await Task.sleep(for: .seconds(3.0))
        siteGateMessage = nil
        endSession(status: "Choose Time In or Time Out to begin.")
        lastScanDate = Date()
    }

    private func presentAlreadyRecorded(match: FaceMatchResult, at timestamp: Date?) async {
        lastMatchName = match.employeeName
        lastMatchConfidence = match.similarity
        lastScanDate = Date()
        successFlash = false
        recognitionState = .alreadyRecorded

        let when = timestamp.map { $0.attendanceDisplay } ?? "earlier today"
        let message = checkType == .checkIn
            ? "\(match.employeeName) already timed in · \(when)"
            : "\(match.employeeName) already timed out · \(when)"
        statusMessage = message

        try? await Task.sleep(for: .seconds(2.5))
        endSession(status: "Choose Time In or Time Out to begin.")
        lastScanDate = Date()
    }
}
