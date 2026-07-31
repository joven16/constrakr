//
//  AttendanceScannerViewModel.swift
//  ConsTrac
//
//  FIX: Hard-reset scanner state, skip warmup frames, require multi-frame consensus,
//  and never keep a previous employee name across scans.
//

import CoreVideo
import Foundation
import SwiftData

enum ScannerRecognitionState {
    case idle
    case noFace
    case unknownPerson
    case poorQuality
    case verifying
    case recognized
    case alreadyRecorded
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
    var pendingConfirmType: CheckType?

    var showsRecognitionDetails: Bool {
        switch recognitionState {
        case .recognized, .alreadyRecorded:
            return lastMatchName != nil && lastMatchConfidence != nil
        default:
            return false
        }
    }

    let cameraManager = CameraManager()

    private let pipeline = FaceRecognitionPipeline()
    private var attendanceService: AttendanceService?
    private var employeeService: EmployeeService?
    private var syncQueue: SyncQueue?
    private var employees: [Employee] = []
    private var lastScanDate: Date?
    private var isHandlingFrame = false
    private var recordedKeysToday: Set<String> = []

    /// Discard frames after camera start / after a completed scan (timing / stale buffer).
    private var warmupFramesRemaining = 0
    /// Consecutive frames that agreed on the same employee above threshold.
    private var consensusEmployeeId: UUID?
    private var consensusCount = 0
    private var consensusBestScore: Float = 0
    private var consensusName: String?

    func configure(context: ModelContext, syncQueue: SyncQueue) {
        attendanceService = AttendanceService(context: context)
        employeeService = EmployeeService(context: context)
        self.syncQueue = syncQueue
        endSession(status: "Choose Time In or Time Out to begin.")
        reloadEmployees()
    }

    func requestConfirm(_ type: CheckType) {
        guard !isProcessing else { return }
        pendingConfirmType = type
    }

    func cancelConfirm() {
        pendingConfirmType = nil
    }

    func confirmPendingType() {
        guard let type = pendingConfirmType else { return }
        pendingConfirmType = nil
        beginSession(type: type)
    }

    func beginSession(type: CheckType) {
        checkType = type
        isSessionActive = true
        hardResetScanner(status: "Position your face for \(type.displayName).")
        warmupFramesRemaining = AppConstants.scannerWarmupFrames
    }

    func endSession(status: String) {
        isSessionActive = false
        pendingConfirmType = nil
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
            cameraManager.onFrame = { [weak self] buffer in
                Task { @MainActor in
                    self?.handleFrame(buffer)
                }
            }
            cameraManager.start()
            cameraError = nil
            statusMessage = "Choose Time In or Time Out to begin."
            recognitionState = .idle
        } catch {
            cameraError = error.localizedDescription
        }
    }

    func stopCamera() {
        cameraManager.onFrame = nil
        cameraManager.stop()
        endSession(status: "Scanner stopped")
    }

    /// Clears previous recognition, consensus, and timing before a new attempt.
    func hardResetScanner(status: String) {
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

    private func clearRecognitionIdentity() {
        lastMatchName = nil
        lastMatchConfidence = nil
    }

    private func resetConsensus() {
        consensusEmployeeId = nil
        consensusCount = 0
        consensusBestScore = 0
        consensusName = nil
    }

    private func recordKey(employeeId: UUID, checkType: CheckType) -> String {
        "\(employeeId.uuidString)-\(checkType.rawValue)"
    }

    private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
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

        do {
            reloadEmployees()
            let match = try pipeline.process(pixelBuffer: pixelBuffer, employees: employees)
            faceDetected = true
            handleConsensusMatch(match)
        } catch FaceRecognitionPipeline.PipelineError.noFaceDetected {
            resetConsensus()
            faceDetected = false
            recognitionState = .noFace
            statusMessage = "No face detected"
        } catch FaceRecognitionPipeline.PipelineError.unknownPerson {
            resetConsensus()
            faceDetected = true
            recognitionState = .unknownPerson
            statusMessage = "Unknown Person"
        } catch FaceRecognitionPipeline.PipelineError.poorQuality(let message) {
            resetConsensus()
            faceDetected = true
            recognitionState = .poorQuality
            statusMessage = message
        } catch {
            resetConsensus()
            recognitionState = .unknownPerson
            statusMessage = "Unknown Person"
            errorMessage = error.localizedDescription
        }
    }

    /// Require several consecutive agreeing frames before saving attendance.
    private func handleConsensusMatch(_ match: FaceMatchResult) {
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

        // Consensus reached — now show identity and record.
        lastMatchName = match.employeeName
        lastMatchConfidence = consensusBestScore
        recognitionState = .recognized
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
        guard !isProcessing, let attendanceService else { return }
        isProcessing = true
        defer { isProcessing = false }

        let key = recordKey(employeeId: match.employeeId, checkType: checkType)

        do {
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

            let attendance = try attendanceService.record(
                employeeId: match.employeeId,
                checkType: checkType,
                confidence: Double(match.similarity),
                notes: "Matched pose: \(match.matchedPose.rawValue)"
            )
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
