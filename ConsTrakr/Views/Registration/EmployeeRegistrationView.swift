//
//  EmployeeRegistrationView.swift
//  ConsTrakr
//

import SwiftUI
import SwiftData
import UIKit

struct EmployeeRegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTabRouter.self) private var tabRouter
    @State private var viewModel = EmployeeRegistrationViewModel()
    @State private var showRegistrationSuccessAlert = false

    var body: some View {
        Group {
            switch viewModel.step {
            case .details:
                detailsStep
            case .faceScan, .done:
                faceScanStep
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(viewModel.step == .details ? .large : .inline)
        .toolbar { toolbarContent }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Registration Complete", isPresented: $showRegistrationSuccessAlert) {
            Button("OK") {
                tabRouter.selectedTab = .employees
                dismiss()
            }
        } message: {
            Text(viewModel.successMessage ?? "Employee registered successfully.")
        }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                viewModel.finishRegistrationAndDismiss()
                showRegistrationSuccessAlert = true
            }
        }
        .onAppear {
            viewModel.configure(context: modelContext)
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }

    // MARK: - Step 1: Details (Settings / Contacts style)

    private var detailsStep: some View {
        Form {
            Section {
                TextField("Employee Code", text: $viewModel.employeeCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                TextField("First Name", text: $viewModel.firstName)
                    .textContentType(.givenName)

                TextField("Last Name", text: $viewModel.lastName)
                    .textContentType(.familyName)

                TextField("Department", text: $viewModel.department)
                    .textContentType(.organizationName)

                JobSitePickerField(selectedSiteId: $viewModel.assignedSiteId)
            } header: {
                Text("Employee Information")
            } footer: {
                Text("Assign a job site for on-site GPS checks at Time In / Time Out. Add sites under More → Job Sites.")
            }

            Section {
                HStack {
                    Label("Face Scan", systemImage: "faceid")
                    Spacer()
                    Text("Next")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Step 2 captures a live face check, optional 3D depth, and five angles for offline recognition.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Step 2: Face scan (fixed layout, no scroll)

    private var faceScanStep: some View {
        GeometryReader { geo in
            let horizontalPad: CGFloat = 16
            let checklistHeight: CGFloat = 40

            VStack(spacing: 12) {
                challengeChecklistBar

                VStack(spacing: 4) {
                    Text(scanStepTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(scanStepSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, horizontalPad)

                cameraCard
                    .frame(
                        width: max(0, geo.size.width - horizontalPad * 2),
                        height: max(
                            180,
                            geo.size.height - checklistHeight - 72
                        )
                    )
                    .padding(.horizontal, horizontalPad)

                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.top, 8)
        }
    }

    /// All enrollment steps — grey until passed, green with checkmark when done.
    private var challengeChecklistBar: some View {
        HStack(spacing: 8) {
            ForEach(allChallengeItems) { item in
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isPassed ? .white : .secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(
                                item.isPassed
                                    ? AnyShapeStyle(Color.green.gradient)
                                    : AnyShapeStyle(Color(.tertiarySystemFill))
                            )
                        )

                    if item.isPassed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white, Color.green)
                            .background(Circle().fill(Color(.systemGroupedBackground)))
                            .offset(x: 4, y: 4)
                    }
                }
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    private struct ChallengeChecklistItem: Identifiable {
        let id: String
        let systemImage: String
        let accessibilityLabel: String
        let isPassed: Bool
    }

    private var allChallengeItems: [ChallengeChecklistItem] {
        var items: [ChallengeChecklistItem] = []

        items.append(ChallengeChecklistItem(
            id: "blink",
            systemImage: "eye.fill",
            accessibilityLabel: viewModel.scanPhase == .blink ? "Blink, not completed" : "Blink passed",
            isPassed: viewModel.scanPhase != .blink
        ))

        if viewModel.cameraManager.isDepthAvailable {
            items.append(ChallengeChecklistItem(
                id: "depth",
                systemImage: "cube.transparent.fill",
                accessibilityLabel: viewModel.scanPhase == .poses ? "3D scan passed" : "3D scan, not completed",
                isPassed: viewModel.scanPhase == .poses
            ))
        }

        for pose in FacePose.allCases {
            let passed = viewModel.capturedEmbeddings[pose] != nil
            items.append(ChallengeChecklistItem(
                id: pose.rawValue,
                systemImage: pose.systemImage,
                accessibilityLabel: passed ? "\(pose.displayName) passed" : "\(pose.displayName), not completed",
                isPassed: passed
            ))
        }

        return items
    }

    private var cameraCard: some View {
        ZStack {
            CameraPreviewView(session: viewModel.cameraManager.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let cameraError = viewModel.cameraError {
                cameraErrorOverlay(cameraError)
            } else {
                FaceGuideOverlay(
                    isConditionMet: viewModel.guideConditionMet,
                    caption: viewModel.primaryInstruction,
                    challenge: viewModel.overlayChallenge,
                    needsLookStraight: viewModel.livenessNeedsLookStraight,
                    pose: viewModel.overlayPose
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(registrationBorderColor, lineWidth: 2.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Toolbar & helpers

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch viewModel.step {
        case .details:
            ToolbarItem(placement: .topBarTrailing) {
                Button("Continue") {
                    viewModel.goToFaceScanStep()
                }
                .fontWeight(.semibold)
                .disabled(!viewModel.isFormValid)
            }
        case .faceScan, .done:
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    viewModel.goBackToDetails()
                }
                .disabled(viewModel.isSaving || viewModel.didSave)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Restart") {
                    viewModel.startEnrollment()
                }
                .disabled(viewModel.isSaving || viewModel.didSave)
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.step {
        case .details: return "New Employee"
        case .faceScan, .done: return "Face Setup"
        }
    }

    private var scanStepTitle: String {
        switch viewModel.scanPhase {
        case .blink:
            return "Blink Slowly"
        case .depthScan:
            return "3D Face Scan"
        case .poses:
            return viewModel.currentPose.displayName
        }
    }

    private var scanStepSubtitle: String {
        switch viewModel.scanPhase {
        case .blink:
            return "Open and close both eyes to confirm you are a live person."
        case .depthScan:
            return "Hold still inside the outline while TrueDepth captures your face shape."
        case .poses:
            return viewModel.currentPose.instruction
        }
    }

    private var registrationBorderColor: Color {
        if viewModel.guideConditionMet { return .green }
        if viewModel.faceDetected { return Color.accentColor }
        return Color(.separator)
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
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
