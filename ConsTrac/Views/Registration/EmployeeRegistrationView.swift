//
//  EmployeeRegistrationView.swift
//  ConsTrac
//

import SwiftUI
import SwiftData
import UIKit

struct EmployeeRegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = EmployeeRegistrationViewModel()

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 20) {
                    switch viewModel.step {
                    case .details:
                        detailsStep
                    case .faceScan:
                        faceScanStep
                    case .done:
                        doneStep
                    }
                }
                .padding()
            }
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.indigo.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Success", isPresented: Binding(
            get: { viewModel.successMessage != nil },
            set: { if !$0 { viewModel.acknowledgeSuccessAndReset() } }
        )) {
            Button("OK") { viewModel.acknowledgeSuccessAndReset() }
        } message: {
            Text(viewModel.successMessage ?? "Employee registered successfully.")
        }
        .onAppear {
            viewModel.configure(context: modelContext)
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(RegistrationStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= viewModel.stepIndex ? Color.indigo : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            Text("Step \(viewModel.stepIndex + 1) of \(viewModel.stepCount): \(viewModel.step.title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var detailsStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Employee details")
                    .font(.title3.bold())
                Text("Fill in the employee profile, then continue to face enrollment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                TextField("Employee Code", text: $viewModel.employeeCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("First Name", text: $viewModel.firstName)
                TextField("Last Name", text: $viewModel.lastName)
                TextField("Department", text: $viewModel.department)
            }
            .textFieldStyle(.roundedBorder)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                viewModel.goToFaceScanStep()
            } label: {
                Label("Continue to Face Scan", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(!viewModel.isFormValid)
        }
    }

    private var faceScanStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.firstName) \(viewModel.lastName)")
                    .font(.headline)
                Text(viewModel.employeeCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                CameraPreviewView(session: viewModel.cameraManager.session)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let cameraError = viewModel.cameraError {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                        Text(cameraError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    PoseGuideOverlay(
                        pose: viewModel.currentPose,
                        faceDetected: viewModel.faceDetected,
                        poseMatched: viewModel.poseMatched,
                        progress: viewModel.enrollmentProgress,
                        capturedCount: viewModel.capturedEmbeddings.count,
                        totalPoses: FacePose.allCases.count,
                        statusMessage: viewModel.statusMessage
                    )
                }
            }

            if !viewModel.capturedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(FacePose.allCases) { pose in
                            if let data = viewModel.capturedPhotos[pose],
                               let image = UIImage(data: data) {
                                VStack(spacing: 4) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(pose.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Back") { viewModel.goBackToDetails() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSaving || viewModel.didSave)

                Button("Restart Scan") { viewModel.startEnrollment() }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(viewModel.isSaving || viewModel.didSave)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(viewModel.successMessage ?? "Employee registered successfully.")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Preparing the form for the next employee…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
