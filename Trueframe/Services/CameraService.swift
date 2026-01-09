// Handles photo capture with thread-safe Actor isolation.

@preconcurrency import AVFoundation
import Combine
import Photos
import UIKit

enum CameraError: Error, LocalizedError {
    case cameraUnavailable
    case configurationFailed
    case notConfigured
    case photoProcessingFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "Camera is not available"
        case .configurationFailed: return "Failed to configure camera"
        case .notConfigured: return "Camera not configured"
        case .photoProcessingFailed: return "Failed to process photo"
        }
    }
}

/// Thread-safe camera service using Actor isolation.
/// All mutable state is protected from data races.
actor CameraService {
    // MARK: - Published State (nonisolated for Combine compatibility)

    private let capturedPhotoSubject = PassthroughSubject<CapturedPhoto, Never>()
    nonisolated var capturedPhoto: AnyPublisher<CapturedPhoto, Never> {
        capturedPhotoSubject.eraseToAnyPublisher()
    }

    // MARK: - Camera Hardware

    private var captureSession: AVCaptureSession?
    private var frontCamera: AVCaptureDevice?
    private var backWideCamera: AVCaptureDevice?
    private var backUltraWideCamera: AVCaptureDevice?
    private var backTelephotoCamera: AVCaptureDevice?
    private var selectedBackCameraType: BackCameraType = .wide
    private var currentInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoOutputDelegate: VideoFrameCaptureDelegate?

    // MARK: - State (Actor-protected)

    private var currentPosition: CameraPosition = .back
    private var configuredBackCameraType: BackCameraType?  // Track which lens is currently configured
    private var pendingCapture: CheckedContinuation<Void, Error>?
    private var isCapturingReactionShot = false
    private(set) var isReady = false
    private(set) var flashEnabled = false
    private var pendingFrameCapture: CheckedContinuation<UIImage?, Never>?

    /// Photo quality settings for capture configuration
    var qualitySettings: PhotoQualitySettings?

    // MARK: - Queues

    private let sessionQueue = DispatchQueue(label: "com.trueframe.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.trueframe.camera.videoOutput")

    // MARK: - Delegate wrapper for AVCapturePhotoCaptureDelegate

    private var delegateWrapper: CameraServiceDelegateWrapper?

    // MARK: - Initialization

    init() {
        discoverCameras()
        delegateWrapper = CameraServiceDelegateWrapper(service: self)
    }

    private func discoverCameras() {
        frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

        // Discover all back camera types
        let backDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )

        for device in backDiscovery.devices {
            switch device.deviceType {
            case .builtInWideAngleCamera:
                backWideCamera = device
            case .builtInUltraWideCamera:
                backUltraWideCamera = device
            case .builtInTelephotoCamera:
                backTelephotoCamera = device
            default:
                break
            }
        }
    }

    private func device(for position: CameraPosition) -> AVCaptureDevice? {
        switch position {
        case .front: return frontCamera
        case .back, .both: return backCamera(for: selectedBackCameraType)
        }
    }

    private func backCamera(for type: BackCameraType) -> AVCaptureDevice? {
        switch type {
        case .wide:
            return backWideCamera
        case .ultrawide:
            return backUltraWideCamera ?? backWideCamera  // Fallback to wide if unavailable
        case .telephoto:
            return backTelephotoCamera ?? backWideCamera  // Fallback to wide if unavailable
        }
    }

    private func configureFaceAutofocus(for device: AVCaptureDevice) throws {
        guard device.isFocusModeSupported(.continuousAutoFocus) else { return }
        try device.lockForConfiguration()
        device.focusMode = .continuousAutoFocus
        device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = true
        device.unlockForConfiguration()
    }

    // MARK: - Public API

    func setQualitySettings(_ settings: PhotoQualitySettings) {
        qualitySettings = settings
    }

    func updateCameraSettings(wide: Bool, ultrawide: Bool, telephoto: Bool, flash: Bool) {
        flashEnabled = flash

        // Determine which camera type is selected (mutually exclusive)
        if ultrawide {
            selectedBackCameraType = .ultrawide
        } else if telephoto {
            selectedBackCameraType = .telephoto
        } else {
            selectedBackCameraType = .wide
        }
    }

    func preWarm() {
        guard !isReady else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.setupSessionSync(for: .back)
                Task { await self.setReady(true) }
            } catch {
                print("[CameraService] PreWarm failed: \(error)")
            }
        }
    }

    private func setReady(_ ready: Bool) {
        isReady = ready
    }

    func configure(for position: CameraPosition) async throws {
        currentPosition = position

        // Skip reconfiguration only if already ready with the same camera
        let needsReconfigure = !isReady ||
            position != .back ||
            configuredBackCameraType != selectedBackCameraType

        guard needsReconfigure else { return }

        // Stop existing session before reconfiguring
        if let session = captureSession {
            session.stopRunning()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }
                do {
                    try self.setupSessionSync(for: position)
                    Task { await self.setReady(true) }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func setupSessionSync(for position: CameraPosition) throws {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let camera = device(for: position) else {
            throw CameraError.cameraUnavailable
        }

        try configureFaceAutofocus(for: camera)

        // Apply quality settings to device if available
        if let settings = qualitySettings {
            try settings.configureDevice(camera)
        }

        let input = try AVCaptureDeviceInput(device: camera)
        let photoOut = AVCapturePhotoOutput()

        // Apply quality settings to output or use defaults
        if let settings = qualitySettings {
            settings.configureOutput(photoOut)
        } else {
            photoOut.maxPhotoQualityPrioritization = .quality
            if photoOut.isResponsiveCaptureSupported { photoOut.isResponsiveCaptureEnabled = true }
            if photoOut.isFastCapturePrioritizationSupported { photoOut.isFastCapturePrioritizationEnabled = true }
            if photoOut.isZeroShutterLagSupported { photoOut.isZeroShutterLagEnabled = true }
        }

        // Add video output for fast burst capture
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.alwaysDiscardsLateVideoFrames = true
        let delegate = VideoFrameCaptureDelegate(service: self)
        videoOut.setSampleBufferDelegate(delegate, queue: videoOutputQueue)

        guard session.canAddInput(input), session.canAddOutput(photoOut), session.canAddOutput(videoOut) else {
            throw CameraError.configurationFailed
        }

        session.addInput(input)
        session.addOutput(photoOut)
        session.addOutput(videoOut)

        currentInput = input
        photoOutput = photoOut
        videoOutput = videoOut
        videoOutputDelegate = delegate
        captureSession = session
        configuredBackCameraType = selectedBackCameraType  // Track which lens was configured
        session.startRunning()
    }

    func capturePhoto() async throws {
        switch currentPosition {
        case .front, .back: try await captureSingle()
        case .both: try await captureBoth()
        }
    }

    private func captureSingle() async throws {
        guard let output = photoOutput else { throw CameraError.notConfigured }
        // Wait for previous capture to complete
        while pendingCapture != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let settings: AVCapturePhotoSettings
        if let qualityConfig = qualitySettings {
            settings = qualityConfig.createPhotoSettings(for: output, flashEnabled: flashEnabled)
        } else {
            settings = AVCapturePhotoSettings()
            settings.flashMode = flashEnabled ? .on : .off
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingCapture = continuation
            guard let delegate = delegateWrapper else {
                pendingCapture?.resume(throwing: CameraError.configurationFailed)
                pendingCapture = nil
                return
            }
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func captureBoth() async throws {
        try await switchCamera(to: .back)
        try await captureSingle()
        try await switchCamera(to: .front)
        try await captureSingle()
    }

    private func switchCamera(to position: CameraPosition) async throws {
        guard let session = captureSession, let camera = device(for: position) else {
            throw CameraError.cameraUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }

                session.beginConfiguration()
                if let current = self.currentInput { session.removeInput(current) }

                do {
                    let newInput = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(newInput) else { throw CameraError.configurationFailed }
                    session.addInput(newInput)
                    self.currentInput = newInput
                    session.commitConfiguration()
                    continuation.resume()
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func tearDown() async {
        isReady = false

        // Resume any pending frame capture to prevent continuation leak
        if let pendingFrame = pendingFrameCapture {
            pendingFrameCapture = nil
            pendingFrame.resume(returning: nil)
        }

        // Resume any pending photo capture
        if let pendingPhoto = pendingCapture {
            pendingCapture = nil
            pendingPhoto.resume(throwing: CameraError.notConfigured)
        }

        let session = captureSession
        captureSession = nil
        currentInput = nil
        photoOutput = nil
        videoOutput = nil
        videoOutputDelegate = nil
        configuredBackCameraType = nil

        // Wait for session to actually stop on its queue
        if let session = session {
            await withCheckedContinuation { continuation in
                sessionQueue.async {
                    session.stopRunning()
                    continuation.resume()
                }
            }
        }
    }

    func captureReactionShot() async throws {
        guard let session = captureSession, let frontCam = frontCamera else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                session.beginConfiguration()
                if let current = self.currentInput { session.removeInput(current) }

                do {
                    try self.configureFaceAutofocus(for: frontCam)
                    let frontInput = try AVCaptureDeviceInput(device: frontCam)
                    guard session.canAddInput(frontInput) else {
                        session.commitConfiguration()
                        continuation.resume()
                        return
                    }

                    session.addInput(frontInput)
                    self.currentInput = frontInput
                    session.commitConfiguration()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        Task {
                            await self.setCapturingReactionShot(true)
                            try? await self.captureSingle()
                            await self.setCapturingReactionShot(false)
                            continuation.resume()
                        }
                    }
                } catch {
                    session.commitConfiguration()
                    continuation.resume()
                }
            }
        }
    }

    private func setCapturingReactionShot(_ value: Bool) {
        isCapturingReactionShot = value
    }

    // MARK: - Delegate Callbacks (called from wrapper)

    /// Handle photo capture error
    func handlePhotoError(_ error: Error) {
        pendingCapture?.resume(throwing: error)
        pendingCapture = nil
    }

    /// Handle successfully captured photo image (already converted from AVCapturePhoto by delegate)
    func handlePhotoImage(_ image: UIImage) {
        let isReaction = isCapturingReactionShot

        // Process image synchronously within actor context
        let correctedImage = image.correctedForOrientation()

        if isReaction {
            saveReactionShotToCameraRoll(correctedImage)
        } else {
            let captured = CapturedPhoto(image: correctedImage)
            capturedPhotoSubject.send(captured)
        }

        pendingCapture?.resume()
        pendingCapture = nil
    }

    private func saveReactionShotToCameraRoll(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.95) else { return }

        Task.detached {
            try? await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "trueframe-reaction-\(UUID().uuidString.prefix(8)).jpg"
                request.addResource(with: .photo, data: imageData, options: options)
                request.creationDate = Date()
            }
        }
    }

    // MARK: - Fast Frame Capture (for burst mode)

    /// Capture a frame from the video stream - much faster than photo capture
    func captureFrame() async -> UIImage? {
        guard isReady else { return nil }
        return await withCheckedContinuation { continuation in
            pendingFrameCapture = continuation
        }
    }

    /// Handle incoming video frame image (already converted from CMSampleBuffer by delegate)
    func handleVideoFrameImage(_ image: UIImage) {
        guard let continuation = pendingFrameCapture else { return }
        pendingFrameCapture = nil

        let corrected = image.correctedForOrientation()
        continuation.resume(returning: corrected)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate Wrapper

/// Wrapper class to handle AVCapturePhotoCaptureDelegate since actors can't directly conform.
/// Extracts image data synchronously during callback to ensure safe async handling.
private final class CameraServiceDelegateWrapper: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private weak var service: CameraService?

    init(service: CameraService) {
        self.service = service
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Capture service reference immediately
        guard let serviceRef = service else { return }

        // Handle errors synchronously
        if let error = error {
            Task {
                await serviceRef.handlePhotoError(error)
            }
            return
        }

        // Extract image data synchronously during callback to ensure validity
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task {
                await serviceRef.handlePhotoError(CameraError.photoProcessingFailed)
            }
            return
        }

        // Now safe to pass UIImage to actor asynchronously
        Task {
            await serviceRef.handlePhotoImage(image)
        }
    }
}

/// Delegate for fast video frame capture
/// IMPORTANT: CMSampleBuffer is only valid during the callback, so we extract the image synchronously.
private final class VideoFrameCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private weak var service: CameraService?
    private let context = CIContext()

    init(service: CameraService) {
        self.service = service
        super.init()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // CRITICAL: Extract image synchronously - CMSampleBuffer is only valid during this callback
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let image = UIImage(cgImage: cgImage)

        // Now safe to pass UIImage to the actor asynchronously
        let serviceRef = service
        Task {
            await serviceRef?.handleVideoFrameImage(image)
        }
    }
}
