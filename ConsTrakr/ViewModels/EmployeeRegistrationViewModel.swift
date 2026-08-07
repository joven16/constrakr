//
//  EmployeeRegistrationViewModel.swift
//  ConsTrakr
//
//  Enrollment: blink → brief 3D scan → five poses.
//  Calm, stable on-screen text (no per-frame hint thrashing).
//

import AVFoundation
import CoreVideo
import Foundation
import SwiftData
import UIKit

enum RegistrationStep: Int, CaseIterable {
    case details = 0
    case idDocument = 1
    case faceScan = 2
    case done = 3

    var title: String {
        switch self {
        case .details: return "Details"
        case .idDocument: return "Scan ID"
        case .faceScan: return "Face Scan"
        case .done: return "Done"
        }
    }
}

enum EnrollScanPhase: Equatable {
    case blink
    case depthScan
    case poses
}

@MainActor
@Observable
final class EmployeeRegistrationViewModel {
    var employeeCode = ""
    var firstName = ""
    var lastName = ""
    var department = ""
    var assignedSiteId: UUID?

    var selectedIdType: IdDocumentType = .philsysNationalId
    var idDocumentNumber = ""
    private(set) var idDocumentImage: UIImage?
    private(set) var idDocumentCapturedAt: Date?
    var showDocumentScanner = false

    private(set) var step: RegistrationStep = .details
    private(set) var currentPose: FacePose = .center
    private(set) var capturedEmbeddings: [FacePose: FaceEmbedding] = [:]
    private(set) var capturedPhotos: [FacePose: Data] = [:]
    private(set) var faceDetected = false
    private(set) var poseMatched = false
    private(set) var isEnrolling = false
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var successMessage: String?
    private(set) var guideConditionMet = false
    private(set) var livenessNeedsLookStraight = false
    private(set) var scanPhase: EnrollScanPhase = .blink
    private(set) var depthScanProgress: Double = 0
    var errorMessage: String?
    private(set) var duplicateFaceMatch: FaceMatchResult?
    private(set) var cameraError: String?

    var showDuplicateFaceAlert: Bool {
        duplicateFaceMatch != nil
    }

    /// Stable line on the camera overlay — changes only when the phase changes.
    private(set) var primaryInstruction = "Blink both eyes slowly"

    var overlayChallenge: LivenessChallenge? {
        guard step == .faceScan, isEnrolling, scanPhase != .poses else { return nil }
        return scanPhase == .depthScan ? .confirm3D : .blink
    }

    var overlayPose: FacePose? {
        guard step == .faceScan, isEnrolling, scanPhase == .poses else { return nil }
        return currentPose
    }

    /// Step dots: blink → 3D → poses (shown as one block after live checks).
    var liveStepNumber: Int {
        switch scanPhase {
        case .blink: return 1
        case .depthScan: return 2
        case .poses: return 3
        }
    }

    let liveStepTotal = 3

    let cameraManager = CameraManager()

    private let detectionService = FaceDetectionService()
    private let embeddingService = FaceEmbeddingService()
    private var livenessChecker = LivenessChecker(challenge: .blink)
    private var depthScanAccumulator = FaceDepthScanAccumulator()
    private var capturedDepthSignature: FaceDepthSignature?
    private var employeeService: EmployeeService?
    private var poseHoldStart: Date?
    private var isProcessingFrame = false

    var enrollmentProgress: Double {
        Double(capturedEmbeddings.count) / Double(FacePose.allCases.count)
    }

    var isFormValid: Bool {
        !employeeCode.trimmingCharacters(in: .whitespaces).isEmpty
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canSave: Bool {
        isFormValid
            && capturedEmbeddings.count == FacePose.allCases.count
            && !isSaving
            && !didSave
            && (capturedDepthSignature != nil || !cameraManager.isDepthAvailable)
    }

    var stepIndex: Int { step.rawValue }
    var stepCount: Int { RegistrationStep.allCases.count }

    func configure(context: ModelContext) {
        employeeService = EmployeeService(context: context)
        if assignedSiteId == nil {
            assignedSiteId = JobSiteStore.defaultSiteId
        }
    }

    func startCamera() async {
        do {
            try await cameraManager.requestAccessAndConfigure()
            cameraManager.onFrame = { [weak self] buffer, depth in
                Task { @MainActor in
                    self?.handleFrame(buffer, depthData: depth)
                }
            }
            cameraManager.start()
            cameraError = nil
        } catch {
            cameraError = error.localizedDescription
        }
    }

    func stopCamera() {
        cameraManager.onFrame = nil
        isProcessingFrame = false
        cameraManager.stop()
    }

    var isIdDocumentStepValid: Bool {
        idDocumentImage != nil
    }

    func goToIdDocumentStep() {
        guard isFormValid else {
            errorMessage = "Fill in employee details before continuing."
            return
        }
        guard !didSave else { return }
        step = .idDocument
        stopCamera()
    }

    func skipIdDocumentStep() {
        guard !didSave else { return }
        idDocumentImage = nil
        idDocumentNumber = ""
        idDocumentCapturedAt = nil
        step = .faceScan
        startEnrollment()
        if !cameraManager.isRunning {
            Task { await startCamera() }
        }
    }

    func goToFaceScanFromIdStep() {
        guard isIdDocumentStepValid else {
            errorMessage = "Scan the government ID or tap Skip to continue without one."
            return
        }
        guard !didSave else { return }
        step = .faceScan
        startEnrollment()
        if !cameraManager.isRunning {
            Task { await startCamera() }
        }
    }

    func goBackToDetailsFromIdStep() {
        guard !didSave, !isSaving else { return }
        step = .details
        stopCamera()
    }

    func handleIdDocumentCapture(_ image: UIImage) {
        idDocumentImage = image
        idDocumentCapturedAt = Date()
        showDocumentScanner = false
    }

    func retakeIdDocument() {
        idDocumentImage = nil
        idDocumentCapturedAt = nil
        showDocumentScanner = true
    }

    func goToFaceScanStep() {
        goToIdDocumentStep()
    }

    func goBackToDetails() {
        if step == .faceScan {
            resetEnrollment(keepStatus: false)
            step = .idDocument
            stopCamera()
            return
        }
        guard !didSave, !isSaving else { return }
        step = .details
        primaryInstruction = "Enter employee details to continue."
        stopCamera()
    }

    func startEnrollment() {
        guard isFormValid, !didSave else { return }
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        capturedDepthSignature = nil
        depthScanAccumulator.reset()
        depthScanProgress = 0
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = true
        didSave = false
        successMessage = nil
        errorMessage = nil
        scanPhase = .blink
        livenessChecker.reset(newChallenge: .blink)
        livenessNeedsLookStraight = false
        guideConditionMet = false
        setInstruction("Blink both eyes slowly")
        if !cameraManager.isRunning {
            Task { await startCamera() }
        }
    }

    func resetEnrollment(keepStatus: Bool = true) {
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        capturedDepthSignature = nil
        depthScanAccumulator.reset()
        depthScanProgress = 0
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = false
        scanPhase = .blink
        guideConditionMet = false
        errorMessage = nil
        if keepStatus {
            setInstruction("Tap Restart Scan to begin again.")
        }
    }

    func saveEmployee() {
        guard canSave, let employeeService else { return }
        isSaving = true
        defer { isSaving = false }

        let embeddings = FacePose.allCases.compactMap { capturedEmbeddings[$0] }
        do {
            _ = try employeeService.register(
                employeeCode: employeeCode,
                firstName: firstName,
                lastName: lastName,
                department: department.isEmpty ? "General" : department,
                assignedSiteId: assignedSiteId,
                embeddings: embeddings,
                faceDepthSignature: capturedDepthSignature,
                enrollmentPhotos: capturedPhotos,
                idDocumentType: idDocumentImage != nil ? selectedIdType : nil,
                idDocumentNumber: idDocumentNumber,
                idDocumentCapturedAt: idDocumentCapturedAt,
                idDocumentImage: idDocumentImage
            )
            didSave = true
            isEnrolling = false
            successMessage = "\(firstName) \(lastName) was registered successfully."
            setInstruction("Registration complete")
            stopCamera()
            NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
        } catch let error as EmployeeService.ServiceError {
            switch error {
            case .duplicateFace(let name, let code):
                presentDuplicateFace(
                    FaceMatchResult(
                        employeeId: UUID(),
                        employeeCode: code,
                        employeeName: name,
                        similarity: 0,
                        matchedPose: .center
                    )
                )
            default:
                errorMessage = error.localizedDescription
                step = .faceScan
            }
        } catch {
            errorMessage = error.localizedDescription
            step = .faceScan
        }
    }

    func dismissDuplicateFaceAlert() {
        duplicateFaceMatch = nil
        resetForNextEmployee()
    }

    func acknowledgeSuccessAndReset() {
        resetForNextEmployee()
    }

    /// Lightweight handoff after the success alert — navigation only, no heavy reset here.
    func finishRegistrationAndDismiss() {
        stopCamera()
    }

    /// Called after the user confirms the registration success prompt.
    func finalizeRegistrationAfterSuccess() {
        finishRegistrationAndDismiss()
    }

    private func resetForNextEmployee() {
        employeeCode = ""
        firstName = ""
        lastName = ""
        department = ""
        assignedSiteId = JobSiteStore.defaultSiteId
        selectedIdType = .philsysNationalId
        idDocumentNumber = ""
        idDocumentImage = nil
        idDocumentCapturedAt = nil
        showDocumentScanner = false
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        capturedDepthSignature = nil
        depthScanAccumulator.reset()
        depthScanProgress = 0
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = false
        isSaving = false
        didSave = false
        successMessage = nil
        errorMessage = nil
        duplicateFaceMatch = nil
        faceDetected = false
        poseMatched = false
        scanPhase = .blink
        guideConditionMet = false
        step = .details
        primaryInstruction = "Enter employee details to continue."
        stopCamera()
    }

    private func setInstruction(_ text: String) {
        guard primaryInstruction != text else { return }
        primaryInstruction = text
    }

    private func beginDepthScan() {
        scanPhase = .depthScan
        depthScanAccumulator.reset()
        depthScanProgress = 0
        setInstruction("Hold still — 3D face scan")
    }

    private func beginPoseCapture() {
        scanPhase = .poses
        currentPose = .center
        poseHoldStart = nil
        setInstruction(currentPose.instruction)
    }

    /// Depth gate during 3D scan — pauses progress on bad frames, never accuses a live user.
    private func depthAllowsProgress(depthData: AVDepthData?, faceBox: CGRect) -> Bool {
        guard cameraManager.isDepthAvailable else { return true }
        guard let depthData else { return false }

        let verdict = DepthFlatnessDetector.evaluate(
            depthData: depthData,
            faceBox: faceBox,
            strict: false
        )
        return !verdict.isFlat
    }

    private func handleFrame(_ pixelBuffer: CVPixelBuffer, depthData: AVDepthData?) {
        guard step == .faceScan, isEnrolling, !didSave else { return }
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        let mirrored = cameraManager.position == .front

        do {
            let frame = try FaceImagePreprocessor.copyPixelBuffer(pixelBuffer)
            let face = try detectionService.primaryFace(in: frame, mirrored: mirrored)
            faceDetected = face != nil

            switch scanPhase {
            case .blink:
                handleBlinkPhase(face: face, mirrored: mirrored)
            case .depthScan:
                handleDepthPhase(face: face, depthData: depthData)
            case .poses:
                try handlePosePhase(frame: frame, face: face, mirrored: mirrored)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleBlinkPhase(face: DetectedFace?, mirrored: Bool) {
        guard let face else {
            guideConditionMet = false
            livenessNeedsLookStraight = false
            return
        }

        let passed = livenessChecker.update(
            hasFace: true,
            yaw: face.yaw,
            pitch: face.pitch,
            leftEyeEAR: face.leftEyeEAR,
            rightEyeEAR: face.rightEyeEAR,
            mirrored: mirrored
        )
        livenessNeedsLookStraight = livenessChecker.needsLookStraight
        guideConditionMet = livenessChecker.isConditionMet

        if passed {
            if cameraManager.isDepthAvailable {
                beginDepthScan()
            } else {
                capturedDepthSignature = nil
                beginPoseCapture()
            }
        }
    }

    private func handleDepthPhase(face: DetectedFace?, depthData: AVDepthData?) {
        guard let face else {
            guideConditionMet = false
            depthScanProgress = depthScanAccumulator.progress
            return
        }

        guard depthAllowsProgress(depthData: depthData, faceBox: face.boundingBox) else {
            guideConditionMet = false
            depthScanProgress = depthScanAccumulator.progress
            return
        }

        guideConditionMet = true
        if let finished = depthScanAccumulator.observe(
            depthData: depthData,
            faceBox: face.boundingBox
        ) {
            capturedDepthSignature = finished
            depthScanProgress = 1
            beginPoseCapture()
        } else {
            depthScanProgress = depthScanAccumulator.progress
        }
    }

    private func handlePosePhase(
        frame: CVPixelBuffer,
        face: DetectedFace?,
        mirrored: Bool
    ) throws {
        guard let face else {
            poseMatched = false
            poseHoldStart = nil
            guideConditionMet = false
            return
        }

        let matched = HeadPoseEstimator.matches(currentPose, yaw: face.yaw, pitch: face.pitch)
        poseMatched = matched
        guideConditionMet = matched

        guard matched else { return }

        if poseHoldStart == nil {
            poseHoldStart = Date()
            setInstruction("Hold still…")
            return
        }

        guard let start = poseHoldStart,
              Date().timeIntervalSince(start) >= AppConstants.poseHoldDuration
        else { return }

        let embedding = try embeddingService.generateEmbedding(
            from: frame,
            face: face,
            pose: currentPose
        )

        if let duplicate = try employeeService?.matchingEnrolledFace(probes: [embedding]) {
            presentDuplicateFace(duplicate)
            return
        }

        if let jpeg = EnrollmentPhotoStore.encodeFaceJPEG(
            from: frame,
            boundingBox: face.boundingBox
        ) {
            capturedPhotos[currentPose] = jpeg
        }

        capturedEmbeddings[currentPose] = embedding
        DebugFrameStore.maybePersistDebugFrame(frame, label: currentPose.rawValue)
        poseHoldStart = nil

        if let next = currentPose.next {
            currentPose = next
            setInstruction(next.instruction)
        } else {
            isEnrolling = false
            setInstruction("Saving…")
            saveEmployee()
        }
    }

    private func presentDuplicateFace(_ match: FaceMatchResult) {
        stopCamera()
        isEnrolling = false
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        capturedDepthSignature = nil
        depthScanAccumulator.reset()
        depthScanProgress = 0
        currentPose = .center
        poseHoldStart = nil
        scanPhase = .blink
        guideConditionMet = false
        faceDetected = false
        poseMatched = false
        setInstruction("Face already registered")
        duplicateFaceMatch = match
    }
}
