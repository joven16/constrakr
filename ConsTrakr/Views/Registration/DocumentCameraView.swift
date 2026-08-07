//
//  DocumentCameraView.swift
//  ConsTrakr
//
//  Manual rear-camera ID capture — no auto-shutter (VisionKit document scan removed).
//

import AVFoundation
import SwiftUI
import UIKit

struct IdDocumentCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = IdDocumentCameraModel()
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isReady {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else if let error = camera.errorMessage {
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera.fill",
                    description: Text(error)
                )
            } else {
                ProgressView("Starting camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .padding()
                    Spacer()
                }

                Spacer()

                Text("Hold the ID steady, then tap Capture")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 16)

                Button {
                    camera.capturePhoto { image in
                        guard let image else { return }
                        onCapture(image)
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 64, height: 64)
                    }
                }
                .disabled(!camera.isReady || camera.isCapturing)
                .padding(.bottom, 36)
            }
        }
        .task {
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }
}

@MainActor
@Observable
final class IdDocumentCameraModel: NSObject {
    let session = AVCaptureSession()

    private(set) var isReady = false
    private(set) var isCapturing = false
    private(set) var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.constrakr.id-document-camera")
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?

    func start() async {
        guard !isReady else { return }

        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }

        guard granted else {
            errorMessage = "Camera access was denied. Enable it in Settings."
            return
        }

        do {
            try await configureSession()
            sessionQueue.async { [weak self] in
                self?.session.startRunning()
            }
            isReady = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        isReady = false
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        captureCompletion = completion

        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraSetupError.unavailable)
                    return
                }

                do {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }

                    for input in self.session.inputs {
                        self.session.removeInput(input)
                    }
                    for output in self.session.outputs {
                        self.session.removeOutput(output)
                    }

                    self.session.sessionPreset = .photo

                    guard let device = AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: .back
                    ) else {
                        throw CameraSetupError.unavailable
                    }

                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        throw CameraSetupError.configurationFailed
                    }
                    self.session.addInput(input)

                    guard self.session.canAddOutput(self.photoOutput) else {
                        throw CameraSetupError.configurationFailed
                    }
                    self.session.addOutput(self.photoOutput)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private enum CameraSetupError: LocalizedError {
        case unavailable
        case configurationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Rear camera is unavailable on this device."
            case .configurationFailed:
                return "Failed to configure the camera for ID capture."
            }
        }
    }
}

extension IdDocumentCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer {
                isCapturing = false
            }

            if error != nil {
                captureCompletion?(nil)
                captureCompletion = nil
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                captureCompletion?(nil)
                captureCompletion = nil
                return
            }

            captureCompletion?(image)
            captureCompletion = nil
        }
    }
}
