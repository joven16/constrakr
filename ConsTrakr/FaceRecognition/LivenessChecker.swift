//
//  LivenessChecker.swift
//  ConsTrakr
//
// Challenge-response liveness to reject static photos / screen spoofs.
// Scanner: blink → one random head turn → move closer.
//

import CoreGraphics
import Foundation

enum LivenessChallenge: CaseIterable {
    case blink
    case turnLeft
    case turnRight
    case nodUp
    case nodDown
    case moveCloser
    case confirm3D

    var instruction: String {
        switch self {
        case .blink: return "Blink both eyes slowly"
        case .turnLeft: return "Turn your head to YOUR left"
        case .turnRight: return "Turn your head to YOUR right"
        case .nodUp: return "Look up, then look straight"
        case .nodDown: return "Look down, then look straight"
        case .moveCloser: return "Move closer to the camera"
        case .confirm3D: return "Hold still — confirming 3D face"
        }
    }

    var systemImage: String {
        switch self {
        case .blink: return "eye"
        case .turnLeft: return "arrow.left"
        case .turnRight: return "arrow.right"
        case .nodUp: return "arrow.up"
        case .nodDown: return "arrow.down"
        case .moveCloser: return "arrow.up.left.and.arrow.down.right"
        case .confirm3D: return "cube.transparent.fill"
        }
    }

    static var headTurns: [LivenessChallenge] {
        [.turnLeft, .turnRight, .nodUp, .nodDown]
    }

    static func randomHeadTurn() -> LivenessChallenge {
        let enabled = FaceScanSettings.enabledSteps
            .filter { $0 != .closeUp }
            .map(\.livenessChallenge)
        return enabled.randomElement() ?? .turnLeft
    }

    /// Scanner gestures from Settings → Face Scanner (blink is always prepended).
    static func configuredScannerSteps() -> [LivenessChallenge] {
        FaceScanSettings.scannerLivenessSteps()
    }
}

enum LivenessPhase: Equatable {
    case waitingForFace
    case performChallenge
    case passed
}

/// Tracks liveness challenges across camera frames.
final class LivenessChecker {
    private(set) var steps: [LivenessChallenge]
    private(set) var stepIndex: Int = 0
    private(set) var challenge: LivenessChallenge
    private(set) var phase: LivenessPhase = .waitingForFace
    private(set) var progressHint: String = "Center your face"
    /// True when the current frame satisfies the active challenge gesture (outline can turn green).
    private(set) var isConditionMet = false

    // Blink tracking (eye aspect ratio).
    private var eyeWasClosed = false
    private var closedFrames = 0
    private var openFrames = 0

    // Head-turn / nod tracking.
    private var sawTargetPose = false
    private var returnToCenterFrames = 0

    // Move-closer tracking.
    private var baselineFaceArea: CGFloat?
    private var closerFrames = 0

    /// Brief face dropouts shouldn't wipe step-1 blink progress.
    private var missingFaceFrames = 0
    private let missingFaceGrace = 8

    private let closedEAR: Float = 0.16
    private let openEAR: Float = 0.21
    private let yawTarget: Double = 0.16
    private let pitchUpTarget: Double = 0.16
    private let pitchDownTarget: Double = -0.12
    private let centerYaw: Double = 0.12
    private let centerPitch: Double = 0.12
    private let closerScale: CGFloat = 1.45

    /// Scanner: blink + enabled gestures from Settings → Face Scanner.
    static func scannerSteps() -> [LivenessChallenge] {
        LivenessChallenge.configuredScannerSteps()
    }

    init(steps: [LivenessChallenge] = [.blink]) {
        self.steps = steps.isEmpty ? [.blink] : steps
        self.challenge = self.steps[0]
        self.progressHint = self.challenge.instruction
    }

    convenience init(challenge: LivenessChallenge) {
        self.init(steps: [challenge])
    }

    func reset(steps: [LivenessChallenge]) {
        self.steps = steps.isEmpty ? [.blink] : steps
        stepIndex = 0
        challenge = self.steps[0]
        phase = .waitingForFace
        progressHint = "Center your face"
        missingFaceFrames = 0
        resetGestureState()
    }

    func reset(newChallenge: LivenessChallenge = .blink) {
        reset(steps: [newChallenge])
    }

    func resetForScanner() {
        reset(steps: Self.scannerSteps())
    }

    var isPassed: Bool { phase == .passed }

    var stepLabel: String {
        "Step \(stepIndex + 1) of \(steps.count)"
    }

    var currentStepNumber: Int { min(stepIndex + 1, steps.count) }
    var totalSteps: Int { max(steps.count, 1) }

    /// True while still on the opening blink challenge.
    var isOnBlinkStep: Bool {
        challenge == .blink && stepIndex == 0 && phase != .passed
    }

    /// After a head turn/nod, user must face the camera again.
    var needsLookStraight: Bool {
        switch challenge {
        case .turnLeft, .turnRight, .nodUp, .nodDown:
            return sawTargetPose && phase != .passed
        case .blink, .moveCloser, .confirm3D:
            return false
        }
    }

    @discardableResult
    func update(
        hasFace: Bool,
        yaw: Double,
        pitch: Double,
        leftEyeEAR: Float?,
        rightEyeEAR: Float?,
        faceArea: CGFloat = 0,
        mirrored: Bool = true
    ) -> Bool {
        guard phase != .passed else { return true }

        guard hasFace else {
            missingFaceFrames += 1
            isConditionMet = false
            if missingFaceFrames >= missingFaceGrace {
                phase = .waitingForFace
                progressHint = "Center your face in the outline"
                resetGestureState()
            } else {
                progressHint = "Keep your face in the outline"
            }
            return false
        }

        missingFaceFrames = 0
        phase = .performChallenge
        if progressHint == "Center your face"
            || progressHint == "Center your face in the outline"
            || progressHint == "Keep your face in the outline" {
            progressHint = challenge.instruction
        }

        switch challenge {
        case .blink:
            updateBlink(leftEyeEAR: leftEyeEAR, rightEyeEAR: rightEyeEAR)
        case .turnLeft:
            let reached = mirrored ? (yaw >= yawTarget) : (yaw <= -yawTarget)
            updateTurn(reached: reached, centered: abs(yaw) < centerYaw && abs(pitch) < centerPitch)
        case .turnRight:
            let reached = mirrored ? (yaw <= -yawTarget) : (yaw >= yawTarget)
            updateTurn(reached: reached, centered: abs(yaw) < centerYaw && abs(pitch) < centerPitch)
        case .nodDown:
            updateTurn(
                reached: pitch <= pitchDownTarget,
                centered: abs(yaw) < centerYaw && abs(pitch) < centerPitch
            )
        case .nodUp:
            updateTurn(
                reached: pitch >= pitchUpTarget,
                centered: abs(yaw) < centerYaw && abs(pitch) < centerPitch
            )
        case .moveCloser:
            updateMoveCloser(faceArea: faceArea)
        case .confirm3D:
            isConditionMet = false
            progressHint = "Hold still — confirming 3D face"
        }

        return isPassed
    }

    private func completeCurrentStep() {
        isConditionMet = true
        if stepIndex + 1 < steps.count {
            stepIndex += 1
            challenge = steps[stepIndex]
            resetGestureState()
            progressHint = "Nice — next: \(challenge.instruction)"
            phase = .performChallenge
        } else {
            phase = .passed
            progressHint = "Liveness verified"
        }
    }

    private func resetGestureState() {
        isConditionMet = false
        eyeWasClosed = false
        closedFrames = 0
        openFrames = 0
        sawTargetPose = false
        returnToCenterFrames = 0
        baselineFaceArea = nil
        closerFrames = 0
    }

    private func updateBlink(leftEyeEAR: Float?, rightEyeEAR: Float?) {
        guard let left = leftEyeEAR, let right = rightEyeEAR else {
            progressHint = "Move a bit closer — need a clearer view of your eyes"
            isConditionMet = false
            return
        }
        let ear = (left + right) / 2
        let eyesClosed = ear < closedEAR
        isConditionMet = eyesClosed || (eyeWasClosed && ear <= openEAR)

        if eyesClosed {
            closedFrames += 1
            openFrames = 0
            if closedFrames >= 2 {
                eyeWasClosed = true
                progressHint = "Good — now open your eyes"
            } else {
                progressHint = challenge.instruction
            }
            return
        }

        // Mid-band (neither clearly open nor closed): keep current progress, don't thrash hints.
        if ear <= openEAR {
            if eyeWasClosed {
                progressHint = "Good — now open your eyes"
            }
            return
        }

        // Clearly open.
        openFrames += 1
        closedFrames = 0
        if eyeWasClosed && openFrames >= 2 {
            completeCurrentStep()
        } else if eyeWasClosed {
            progressHint = "Good — now open your eyes"
        } else {
            progressHint = challenge.instruction
        }
    }

    private func updateTurn(reached: Bool, centered: Bool) {
        if reached {
            sawTargetPose = true
            returnToCenterFrames = 0
            isConditionMet = true
            progressHint = "Now look straight at the camera"
            return
        }
        guard sawTargetPose else {
            isConditionMet = false
            progressHint = challenge.instruction
            return
        }
        if centered {
            returnToCenterFrames += 1
            isConditionMet = true
            if returnToCenterFrames >= 3 {
                completeCurrentStep()
            }
        } else {
            returnToCenterFrames = 0
            isConditionMet = false
            progressHint = "Now look straight at the camera"
        }
    }

    private func updateMoveCloser(faceArea: CGFloat) {
        guard faceArea > 0.001 else {
            isConditionMet = false
            return
        }
        if baselineFaceArea == nil {
            baselineFaceArea = faceArea
            progressHint = "Move closer to the camera"
            isConditionMet = false
            return
        }
        guard let baseline = baselineFaceArea else { return }
        let ratio = faceArea / max(baseline, 0.0001)
        if ratio >= closerScale {
            closerFrames += 1
            isConditionMet = true
            progressHint = "Good — hold there"
            if closerFrames >= 4 {
                completeCurrentStep()
            }
        } else {
            closerFrames = 0
            isConditionMet = ratio >= closerScale * 0.85
            progressHint = "Move closer to the camera"
        }
    }
}

enum LivenessMetrics {
    /// Eye Aspect Ratio from Vision eye landmarks (lower ≈ more closed).
    static func eyeAspectRatio(points: [CGPoint]) -> Float? {
        guard points.count >= 4 else { return nil }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max()
        else { return nil }

        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0)
        return Float(height / width)
    }
}
