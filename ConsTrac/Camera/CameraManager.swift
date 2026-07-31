//
//  CameraManager.swift
//  ConsTrac
//

import AVFoundation
import CoreImage
import UIKit

/// Manages the front-camera AVCaptureSession and delivers sample buffers for Vision processing.
final class CameraManager: NSObject, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case permissionDenied
        case cameraUnavailable
        case configurationFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Camera access was denied. Enable it in Settings."
            case .cameraUnavailable: return "Front camera is unavailable on this device."
            case .configurationFailed: return "Failed to configure the camera session."
            }
        }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.constrac.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    var onFrame: ((CVPixelBuffer) -> Void)?

    var isRunning: Bool { session.isRunning }

    func requestAccessAndConfigure() async throws {
        let granted: Bool
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            granted = true
        } else {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else { throw CameraError.permissionDenied }
        try await configureSession()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }
                do {
                    try self.configureLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureLocked() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            session.commitConfiguration()
            throw CameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.constrac.camera.frames"))

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
