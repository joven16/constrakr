//
//  CameraManager.swift
//  ConsTrakr
//

import AVFoundation
import CoreImage
import QuartzCore
import UIKit

/// Manages the AVCaptureSession and delivers sample buffers for Vision processing.
/// Front camera prefers TrueDepth; video frames are always delivered even if depth drops.
final class CameraManager: NSObject, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case permissionDenied
        case cameraUnavailable
        case configurationFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Camera access was denied. Enable it in Settings."
            case .cameraUnavailable: return "Camera is unavailable on this device."
            case .configurationFailed: return "Failed to configure the camera session."
            }
        }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.constrakr.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let frameQueue = DispatchQueue(label: "com.constrakr.camera.frames")
    private let depthLock = NSLock()
    private var latestDepthData: AVDepthData?
    private var latestDepthTime: CFTimeInterval = 0
    private var isConfigured = false
    private(set) var position: AVCaptureDevice.Position = .front
    /// True when the active input can deliver TrueDepth maps (front only).
    private(set) var isDepthAvailable = false

    /// Video frame plus optional latest depth (TrueDepth front camera).
    var onFrame: ((CVPixelBuffer, AVDepthData?) -> Void)?

    var isRunning: Bool { session.isRunning }

    func requestAccessAndConfigure() async throws {
        let granted: Bool
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            granted = true
        } else {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else { throw CameraError.permissionDenied }
        try await configureSession(position: position)
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

    private func configureSession(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }
                do {
                    try self.configureLocked(position: position, force: false)
                    self.position = position
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureLocked(position: AVCaptureDevice.Position, force: Bool) throws {
        if isConfigured && !force { return }

        session.beginConfiguration()

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        depthLock.lock()
        latestDepthData = nil
        latestDepthTime = 0
        depthLock.unlock()
        isDepthAvailable = false

        let device = Self.bestDevice(for: position)
        guard let device else {
            session.commitConfiguration()
            throw CameraError.cameraUnavailable
        }

        if position == .front {
            session.sessionPreset = .inputPriority
            try Self.configureTrueDepthFormat(device: device)
        } else {
            session.sessionPreset = .high
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
        // Always drive scanning from the video callback so a depth glitch cannot freeze frames.
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
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
                connection.isVideoMirrored = position == .front
            }
        }

        let supportsDepth = position == .front
            && !device.activeFormat.supportedDepthDataFormats.isEmpty
            && session.canAddOutput(depthOutput)

        if supportsDepth {
            depthOutput.isFilteringEnabled = true
            depthOutput.alwaysDiscardsLateDepthData = true
            depthOutput.setDelegate(self, callbackQueue: frameQueue)
            session.addOutput(depthOutput)
            if let depthConnection = depthOutput.connection(with: .depthData),
               depthConnection.isVideoMirroringSupported {
                depthConnection.isVideoMirrored = true
            }
            isDepthAvailable = true
        }

        session.commitConfiguration()
        isConfigured = true
        self.position = position
    }

    private static func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front,
           let trueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            return trueDepth
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private static func configureTrueDepthFormat(device: AVCaptureDevice) throws {
        let candidates = device.formats.filter { !$0.supportedDepthDataFormats.isEmpty }
        guard !candidates.isEmpty else { return }

        let preferred = candidates.min { a, b in
            let wa = abs(Int(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width) - 1280)
            let wb = abs(Int(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width) - 1280)
            return wa < wb
        } ?? candidates[0]

        let depthPreferred = preferred.supportedDepthDataFormats.first {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
        } ?? preferred.supportedDepthDataFormats.first {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DisparityFloat32
        } ?? preferred.supportedDepthDataFormats.first

        try device.lockForConfiguration()
        device.activeFormat = preferred
        if let depthPreferred {
            device.activeDepthDataFormat = depthPreferred
        }
        device.unlockForConfiguration()
    }

    private func currentDepth() -> AVDepthData? {
        depthLock.lock()
        defer { depthLock.unlock() }
        // Ignore stale depth so a flat laptop frame can't ride an older good map.
        guard latestDepthTime > 0, CACurrentMediaTime() - latestDepthTime < 0.35 else {
            return nil
        }
        return latestDepthData
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, currentDepth())
    }
}

extension CameraManager: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        depthLock.lock()
        latestDepthData = depthData
        latestDepthTime = CACurrentMediaTime()
        depthLock.unlock()
    }

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didDrop depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection,
        reason: AVCaptureOutput.DataDroppedReason
    ) {
        // Keep last good depth; video callback continues regardless.
    }
}
