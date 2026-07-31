//
//  PoseGuideOverlay.swift
//  ConsTrac
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

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("\(capturedCount)/\(totalPoses)", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Image(systemName: pose.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(poseMatched ? .green : .white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.horizontal)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 140, style: .continuous)
                    .strokeBorder(
                        faceDetected ? (poseMatched ? Color.green : Color.yellow) : Color.white.opacity(0.7),
                        style: StrokeStyle(lineWidth: 4, dash: faceDetected ? [] : [10, 8])
                    )
                    .frame(width: 240, height: 320)

                VStack(spacing: 8) {
                    Text(pose.displayName)
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
                .tint(.cyan)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
        .padding(.vertical)
    }
}
