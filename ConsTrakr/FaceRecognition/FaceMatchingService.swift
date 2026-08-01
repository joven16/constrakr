//
//  FaceMatchingService.swift
//  ConsTrakr
//
//  FIX: Per-employee multi-pose verification + stricter gallery gate.
//  Never return nearest employee when checks fail.
//

import Foundation
import os

struct FaceMatchResult {
    let employeeId: UUID
    let employeeCode: String
    let employeeName: String
    let similarity: Float
    let matchedPose: FacePose
}

struct FaceMatchDiagnostics {
    let bestSimilarity: Float
    let secondBestSimilarity: Float
    let meanPoseSimilarity: Float
    let threshold: Float
    let margin: Float
    let probeLength: Int
    let probeNorm: Float
    let employeeCountScored: Int
    let accepted: Bool
    let resultLabel: String
}

@MainActor
final class FaceMatchingService {
    var threshold: Float
    var minimumMargin: Float
    private let logger = Logger(subsystem: "com.constrakr", category: "FaceMatch")

    init(
        threshold: Float? = nil,
        minimumMargin: Float? = nil
    ) {
        self.threshold = threshold ?? MatchThresholdSettings.current
        self.minimumMargin = minimumMargin ?? MatchThresholdSettings.margin
    }

    func reloadThresholdFromSettings() {
        threshold = MatchThresholdSettings.current
        minimumMargin = MatchThresholdSettings.margin
    }

    @discardableResult
    func match(
        probe: FaceEmbedding,
        against employees: [Employee]
    ) -> (result: FaceMatchResult?, diagnostics: FaceMatchDiagnostics) {
        reloadThresholdFromSettings()

        let probeValues = FaceImagePreprocessor.l2Normalize(probe.values)
        let probeNorm = FaceImagePreprocessor.l2Norm(probeValues)
        let enrolled = employees.filter(\.isEnrolled)

        // Solo gallery cannot use second-best margin → require a stricter absolute score.
        let effectiveThreshold: Float = enrolled.count <= 1
            ? max(threshold, MatchThresholdSettings.soloFloor)
            : threshold

        struct Candidate {
            let result: FaceMatchResult
            let meanPoseScore: Float
        }

        var candidates: [Candidate] = []

        for employee in enrolled {
            var poseScores: [(FacePose, Float)] = []
            for enrolledEmb in employee.faceEmbeddings {
                // Only compare same-dimension embeddings (AdaFace 512 vs legacy handcrafted).
                guard enrolledEmb.values.count == probeValues.count else { continue }
                let score = FaceImagePreprocessor.cosineSimilarity(probeValues, enrolledEmb.values)
                poseScores.append((enrolledEmb.pose, score))
                #if DEBUG
                print("[ConsTrakr][Match] vs \(employee.employeeCode)/\(enrolledEmb.pose.rawValue) sim=\(String(format: "%.4f", score))")
                #endif
            }
            guard !poseScores.isEmpty else { continue }

            let bestPose = poseScores.max(by: { $0.1 < $1.1 })!
            // Average only the strongest poses — left/right/up/down naturally score lower
            // against a frontal scanner probe and were rejecting real matches.
            let topScores = poseScores.map(\.1).sorted(by: >)
            let topCount = min(2, topScores.count)
            let topMean = topScores.prefix(topCount).reduce(0, +) / Float(topCount)

            let meanFloor = effectiveThreshold - AppConstants.multiPoseMeanSlack
            guard bestPose.1 >= effectiveThreshold, topMean >= meanFloor else { continue }

            candidates.append(
                Candidate(
                    result: FaceMatchResult(
                        employeeId: employee.id,
                        employeeCode: employee.employeeCode,
                        employeeName: employee.fullName,
                        similarity: bestPose.1,
                        matchedPose: bestPose.0
                    ),
                    meanPoseScore: topMean
                )
            )
        }

        candidates.sort { $0.result.similarity > $1.result.similarity }
        let best = candidates.first?.result
        let bestScore = best?.similarity ?? -1
        let secondBestScore = candidates.dropFirst().first?.result.similarity ?? -1
        let meanPoseOfBest = candidates.first?.meanPoseScore ?? -1

        let passesMargin = secondBestScore < 0 || (bestScore - secondBestScore) >= minimumMargin
        let accepted = best != nil && passesMargin

        let label = accepted ? "MATCH \(best!.employeeName)" : "Unknown Person"

        let diagnostics = FaceMatchDiagnostics(
            bestSimilarity: bestScore,
            secondBestSimilarity: secondBestScore,
            meanPoseSimilarity: meanPoseOfBest,
            threshold: effectiveThreshold,
            margin: minimumMargin,
            probeLength: probeValues.count,
            probeNorm: probeNorm,
            employeeCountScored: enrolled.count,
            accepted: accepted,
            resultLabel: label
        )

        #if DEBUG
        print("""
            [ConsTrakr][Match][Summary]
              embeddingLength=\(diagnostics.probeLength)
              embeddingNorm=\(String(format: "%.4f", diagnostics.probeNorm))
              best=\(String(format: "%.4f", diagnostics.bestSimilarity))
              secondBest=\(String(format: "%.4f", diagnostics.secondBestSimilarity))
              meanPose=\(String(format: "%.4f", diagnostics.meanPoseSimilarity))
              threshold=\(String(format: "%.4f", diagnostics.threshold))
              margin=\(String(format: "%.4f", diagnostics.margin))
              gallery=\(diagnostics.employeeCountScored)
              final=\(diagnostics.resultLabel)
            """)
        #endif

        logger.info("Match \(label) best=\(bestScore) second=\(secondBestScore) thr=\(effectiveThreshold)")

        return (accepted ? best : nil, diagnostics)
    }

    func findDuplicateFace(
        probes: [FaceEmbedding],
        against employees: [Employee],
        excludingEmployeeId: UUID? = nil
    ) -> FaceMatchResult? {
        var best: FaceMatchResult?
        let filtered = employees.filter { $0.id != excludingEmployeeId }
        for probe in probes {
            let (match, _) = match(probe: probe, against: filtered)
            if let match, best == nil || match.similarity > best!.similarity {
                best = match
            }
        }
        return best
    }
}
