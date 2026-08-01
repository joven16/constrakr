//
//  PoseGuideOverlay.swift
//  ConsTrakr
//

import SwiftUI

struct PoseGuideOverlay: View {
    let pose: FacePose
    let faceDetected: Bool
    let poseMatched: Bool
    let progress: Double
    let capturedCount: Int
    let totalPoses: Int
    let statusMessage: String
    var livenessPassed: Bool = true
    var depthScanPassed: Bool = true
    var depthScanProgress: Double = 0
    var livenessSystemImage: String = "eye"

    private var inDepthScan: Bool {
        livenessPassed && !depthScanPassed
    }

    private var inPoseCapture: Bool {
        livenessPassed && depthScanPassed
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                phaseBadge
                Spacer()
                Image(systemName: phaseIcon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(phaseIconColor)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.horizontal)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 140, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        style: StrokeStyle(lineWidth: 4, dash: faceDetected && inPoseCapture ? [] : [10, 8])
                    )
                    .frame(width: 240, height: 320)

                if inDepthScan {
                    // Subtle scan sweep to signal active 3D capture.
                    RoundedRectangle(cornerRadius: 140, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.0),
                                    Color.cyan.opacity(0.22),
                                    Color.cyan.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 236, height: 316)
                        .mask(
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(height: max(40, geo.size.height * depthScanProgress))
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                        )
                        .animation(.easeInOut(duration: 0.25), value: depthScanProgress)
                }

                VStack(spacing: 8) {
                    Text(phaseTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(statusMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            ProgressView(value: progress)
                .tint(inDepthScan ? .cyan : .cyan)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
        .padding(.vertical)
    }

    private var phaseBadge: some View {
        Group {
            if !livenessPassed {
                Label("Live check", systemImage: "person.fill.checkmark")
            } else if !depthScanPassed {
                Label(
                    String(format: "3D scan %.0f%%", depthScanProgress * 100),
                    systemImage: "cube.transparent"
                )
            } else {
                Label("\(capturedCount)/\(totalPoses)", systemImage: "checkmark.circle")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var phaseTitle: String {
        if !livenessPassed { return "Live person check" }
        if !depthScanPassed { return "3D face scan" }
        return pose.displayName
    }

    private var phaseIcon: String {
        if !livenessPassed { return livenessSystemImage }
        if !depthScanPassed { return "cube.transparent.fill" }
        return pose.systemImage
    }

    private var phaseIconColor: Color {
        if !livenessPassed { return .purple }
        if !depthScanPassed { return .cyan }
        return poseMatched ? .green : .white
    }

    private var strokeColor: Color {
        if !livenessPassed {
            return faceDetected ? .purple : .white.opacity(0.7)
        }
        if !depthScanPassed {
            return faceDetected ? .cyan : .white.opacity(0.7)
        }
        return faceDetected ? (poseMatched ? Color.green : Color.yellow) : Color.white.opacity(0.7)
    }
}
