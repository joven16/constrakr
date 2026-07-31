//
//  EmployeeRegistrationViewModel.swift
//  ConsTrac
//

import CoreVideo
import Foundation
import SwiftData

enum RegistrationStep: Int, CaseIterable {
    case details = 0
    case faceScan = 1
    case done = 2

    var title: String {
        switch self {
        case .details: return "Details"
        case .faceScan: return "Face Scan"
        case .done: return "Done"
        }
    }
}

@MainActor
@Observable
final class EmployeeRegistrationViewModel {
    var employeeCode = ""
    var firstName = ""
    var lastName = ""
    var department = ""

    private(set) var step: RegistrationStep = .details
    private(set) var currentPose: FacePose = .center
    private(set) var capturedEmbeddings: [FacePose: FaceEmbedding] = [:]
    private(set) var capturedPhotos: [FacePose: Data] = [:]
    private(set) var faceDetected = false
    private(set) var poseMatched = false
    private(set) var detectedPose: FacePose = .center
    private(set) var statusMessage = "Enter employee details to continue."
    private(set) var isEnrolling = false
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var successMessage: String?
    var errorMessage: String?
    private(set) var cameraError: String?

    let cameraManager = CameraManager()

    private let detectionService = FaceDetectionService()
    private let embeddingService = FaceEmbeddingService()
    private var employeeService: EmployeeService?
    private var poseHoldStart: Date?
    private var isProcessingFrame = false
    private var resetTask: Task<Void, Never>?

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
    }

    var stepIndex: Int { step.rawValue }
    var stepCount: Int { RegistrationStep.allCases.count }

    func configure(context: ModelContext) {
        employeeService = EmployeeService(context: context)
    }

    func startCamera() async {
        do {
            try await cameraManager.requestAccessAndConfigure()
            cameraManager.onFrame = { [weak self] buffer in
                Task { @MainActor in
                    self?.handleFrame(buffer)
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
        cameraManager.stop()
    }

    func goToFaceScanStep() {
        guard isFormValid else {
            errorMessage = "Fill in employee details before continuing."
            return
        }
        guard !didSave else { return }
        step = .faceScan
        startEnrollment()
        if !cameraManager.isRunning {
            Task { await startCamera() }
        }
    }

    func goBackToDetails() {
        guard !didSave, !isSaving else { return }
        resetEnrollment(keepStatus: false)
        step = .details
        statusMessage = "Enter employee details to continue."
        stopCamera()
    }

    func startEnrollment() {
        guard isFormValid else {
            errorMessage = "Fill in employee details before enrollment."
            return
        }
        guard !didSave else { return }
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = true
        didSave = false
        successMessage = nil
        errorMessage = nil
        statusMessage = currentPose.instruction
        if !cameraManager.isRunning {
            Task { await startCamera() }
        }
    }

    func resetEnrollment(keepStatus: Bool = true) {
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = false
        errorMessage = nil
        if keepStatus {
            statusMessage = "Enrollment reset. Tap Start Face Scan to begin again."
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
                embeddings: embeddings,
                enrollmentPhotos: capturedPhotos
            )
            didSave = true
            isEnrolling = false
            step = .done
            successMessage = "Employee registered successfully."
            statusMessage = successMessage ?? ""
            scheduleAutoReset()
        } catch {
            errorMessage = error.localizedDescription
            step = .faceScan
        }
    }

    func acknowledgeSuccessAndReset() {
        resetTask?.cancel()
        resetTask = nil
        resetForNextEmployee()
    }

    private func scheduleAutoReset() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.registrationResetDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.resetForNextEmployee()
            }
        }
    }

    private func resetForNextEmployee() {
        employeeCode = ""
        firstName = ""
        lastName = ""
        department = ""
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = false
        isSaving = false
        didSave = false
        successMessage = nil
        errorMessage = nil
        faceDetected = false
        poseMatched = false
        step = .details
        statusMessage = "Enter employee details to continue."
        stopCamera()
    }

    private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        guard step == .faceScan, isEnrolling, !isProcessingFrame, !didSave else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        do {
            guard let face = try detectionService.primaryFace(in: pixelBuffer) else {
                faceDetected = false
                poseMatched = false
                poseHoldStart = nil
                statusMessage = "No face detected — center your face in the frame."
                return
            }

            faceDetected = true
            detectedPose = face.estimatedPose
            let matched = HeadPoseEstimator.matches(currentPose, yaw: face.yaw, pitch: face.pitch)
            poseMatched = matched

            guard matched else {
                poseHoldStart = nil
                if detectedPose == currentPose {
                    statusMessage = "Almost — turn a bit more for \(currentPose.displayName)"
                } else {
                    statusMessage = "Seeing \(detectedPose.displayName). \(currentPose.instruction)"
                }
                return
            }

            if poseHoldStart == nil {
                poseHoldStart = Date()
                statusMessage = "Hold still…"
                return
            }

            guard let start = poseHoldStart,
                  Date().timeIntervalSince(start) >= AppConstants.poseHoldDuration
            else { return }

            let embedding = try embeddingService.generateEmbedding(
                from: pixelBuffer,
                face: face,
                pose: currentPose
            )

            if let duplicate = try employeeService?.matchingEnrolledFace(probes: [embedding]) {
                rejectDuplicateFace(duplicate)
                return
            }

            if let jpeg = EnrollmentPhotoStore.encodeFaceJPEG(
                from: pixelBuffer,
                boundingBox: face.boundingBox
            ) {
                capturedPhotos[currentPose] = jpeg
            }

            capturedEmbeddings[currentPose] = embedding
            DebugFrameStore.maybePersistDebugFrame(pixelBuffer, label: currentPose.rawValue)
            poseHoldStart = nil

            if let next = currentPose.next {
                currentPose = next
                statusMessage = "Captured! Next: \(next.instruction)"
            } else {
                isEnrolling = false
                statusMessage = "All poses captured. Saving…"
                saveEmployee()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rejectDuplicateFace(_ match: FaceMatchResult) {
        let message = "This face already belongs to \(match.employeeName) (\(match.employeeCode)). Registration stopped."
        // Full form reset so the user starts clean for a different employee.
        employeeCode = ""
        firstName = ""
        lastName = ""
        department = ""
        capturedEmbeddings.removeAll()
        capturedPhotos.removeAll()
        currentPose = .center
        poseHoldStart = nil
        isEnrolling = false
        isSaving = false
        didSave = false
        successMessage = nil
        faceDetected = false
        poseMatched = false
        step = .details
        statusMessage = "Enter employee details to continue."
        errorMessage = message
        stopCamera()
    }
}
