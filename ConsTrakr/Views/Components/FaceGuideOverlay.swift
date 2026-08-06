//
//  FaceGuideOverlay.swift
//  ConsTrakr
//
//  Head / face outline guide so the employee aligns inside the scanner frame.
//

import SwiftUI

struct FaceGuideOverlay: View {
    /// When true (live-check gesture met / face ready), outline turns green.
    var isConditionMet: Bool = false
    var caption: String = "Align face inside the outline"
    /// Active live-check challenge — drives large directional arrows.
    var challenge: LivenessChallenge? = nil
    /// After a turn/nod, cue the user to face the camera again.
    var needsLookStraight: Bool = false

    /// Active pose for enrollment pose-capture (shows direction arrows).
    var pose: FacePose? = nil
    /// Scanner: fixed nose target inside the oval for 3D / face alignment.
    var showsNoseTarget: Bool = false

    var body: some View {
        GeometryReader { geo in
            let ovalWidth = min(geo.size.width * 0.62, 260)
            let ovalHeight = ovalWidth * 1.28
            let guideColor = isConditionMet ? Color.green : Color.white.opacity(0.95)
            let arrowSize = min(geo.size.width * 0.22, 88)

            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.32))
                    .mask {
                        ZStack {
                            Rectangle().fill(.white)
                            Ellipse()
                                .frame(width: ovalWidth, height: ovalHeight)
                                .blendMode(.destinationOut)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .compositingGroup()
                    }

                Ellipse()
                    .strokeBorder(
                        guideColor,
                        style: StrokeStyle(
                            lineWidth: isConditionMet ? 4.5 : 3,
                            dash: isConditionMet ? [] : [12, 8]
                        )
                    )
                    .frame(width: ovalWidth, height: ovalHeight)
                    .shadow(color: isConditionMet ? .green.opacity(0.5) : .clear, radius: 10)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: ovalWidth * 0.72, weight: .ultraLight))
                    .foregroundStyle(guideColor.opacity(isConditionMet ? 0.22 : 0.16))
                    .frame(width: ovalWidth, height: ovalHeight)

                if showsNoseTarget {
                    let markSize = min(ovalWidth * 0.14, 36)
                    let labelBlock = markSize * 0.14 + max(9, markSize * 0.28)
                    noseAlignmentMark(
                        color: guideColor,
                        size: markSize
                    )
                    .position(
                        x: geo.size.width / 2,
                        y: geo.size.height / 2 + ovalHeight * 0.06 + labelBlock / 2
                    )
                }

                if let challenge {
                    challengeArrows(
                        challenge: challenge,
                        needsLookStraight: needsLookStraight,
                        ovalWidth: ovalWidth,
                        ovalHeight: ovalHeight,
                        arrowSize: arrowSize,
                        color: guideColor,
                        canvas: geo.size
                    )
                } else if let pose {
                    poseArrows(
                        pose: pose,
                        ovalWidth: ovalWidth,
                        ovalHeight: ovalHeight,
                        arrowSize: arrowSize,
                        color: guideColor,
                        canvas: geo.size
                    )
                }

                VStack {
                    Spacer()
                    Text(caption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(10, (geo.size.height - ovalHeight) / 2 - 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func challengeArrows(
        challenge: LivenessChallenge,
        needsLookStraight: Bool,
        ovalWidth: CGFloat,
        ovalHeight: CGFloat,
        arrowSize: CGFloat,
        color: Color,
        canvas: CGSize
    ) -> some View {
        let midX = canvas.width / 2
        let midY = canvas.height / 2
        let sideGap = ovalWidth * 0.58
        let verticalGap = ovalHeight * 0.58

        if needsLookStraight {
            lookStraightCue(size: arrowSize * 1.05, color: color)
                .position(x: midX, y: midY - verticalGap * 0.15)
        } else {
            switch challenge {
            case .blink:
                bigArrow("eye.fill", size: arrowSize * 0.95, color: color)
                    .position(x: midX, y: midY - verticalGap)
            case .turnLeft:
                bigArrow("arrowshape.left.fill", size: arrowSize, color: color)
                    .position(x: midX - sideGap, y: midY)
            case .turnRight:
                bigArrow("arrowshape.right.fill", size: arrowSize, color: color)
                    .position(x: midX + sideGap, y: midY)
            case .nodUp:
                bigArrow("arrowshape.up.fill", size: arrowSize, color: color)
                    .position(x: midX, y: midY - verticalGap * 0.85)
            case .nodDown:
                bigArrow("arrowshape.down.fill", size: arrowSize, color: color)
                    .position(x: midX, y: midY + verticalGap * 0.85)
            case .moveCloser:
                bigArrow("arrow.up.left.and.arrow.down.right", size: arrowSize * 0.9, color: color)
                    .position(x: midX, y: midY - verticalGap)
            case .confirm3D:
                bigArrow("cube.transparent.fill", size: arrowSize * 0.85, color: color)
                    .position(x: midX, y: midY - verticalGap * 0.9)
            }
        }
    }

    @ViewBuilder
    private func poseArrows(
        pose: FacePose,
        ovalWidth: CGFloat,
        ovalHeight: CGFloat,
        arrowSize: CGFloat,
        color: Color,
        canvas: CGSize
    ) -> some View {
        let midX = canvas.width / 2
        let midY = canvas.height / 2
        let sideGap = ovalWidth * 0.58
        let verticalGap = ovalHeight * 0.58

        switch pose {
        case .center:
            lookStraightCue(size: arrowSize * 1.05, color: color)
                .position(x: midX, y: midY - verticalGap * 0.15)
        case .left:
            bigArrow("arrowshape.left.fill", size: arrowSize, color: color)
                .position(x: midX - sideGap, y: midY)
        case .right:
            bigArrow("arrowshape.right.fill", size: arrowSize, color: color)
                .position(x: midX + sideGap, y: midY)
        case .up:
            bigArrow("arrowshape.up.fill", size: arrowSize, color: color)
                .position(x: midX, y: midY - verticalGap * 0.85)
        case .down:
            bigArrow("arrowshape.down.fill", size: arrowSize, color: color)
                .position(x: midX, y: midY + verticalGap * 0.85)
        }
    }

    private func noseAlignmentMark(color: Color, size: CGFloat) -> some View {
        VStack(spacing: size * 0.14) {
            ZStack {
                Circle()
                    .strokeBorder(
                        color.opacity(isConditionMet ? 0.95 : 0.75),
                        style: StrokeStyle(lineWidth: 2, dash: isConditionMet ? [] : [4, 4])
                    )
                    .frame(width: size, height: size)

                Rectangle()
                    .fill(color.opacity(0.85))
                    .frame(width: size * 0.72, height: 1.5)

                Rectangle()
                    .fill(color.opacity(0.85))
                    .frame(width: 1.5, height: size * 0.72)

                Circle()
                    .fill(color.opacity(isConditionMet ? 0.95 : 0.8))
                    .frame(width: size * 0.22, height: size * 0.22)
            }
            .frame(width: size, height: size)

            Text("NOSE")
                .font(.system(size: max(9, size * 0.28), weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(color)
                .fixedSize()
        }
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .accessibilityLabel("Align your nose on the target")
    }

    private func lookStraightCue(size: CGFloat, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: size * 0.38, weight: .bold))
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: size * 0.55, weight: .semibold))
            Text("LOOK HERE")
                .font(.caption.weight(.heavy))
                .tracking(0.6)
        }
        .foregroundStyle(color)
        .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(color.opacity(0.9), lineWidth: 3)
                }
        )
        .symbolEffect(.pulse, options: .repeating, isActive: !isConditionMet)
    }

    private func bigArrow(_ systemName: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.72, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.black.opacity(0.45))
                    .overlay {
                        Circle().strokeBorder(color.opacity(0.85), lineWidth: 3)
                    }
            )
            .symbolEffect(.pulse, options: .repeating, isActive: !isConditionMet)
    }
}
