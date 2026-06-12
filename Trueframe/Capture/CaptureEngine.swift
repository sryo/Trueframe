// Captures full-resolution photos at burst cadence using responsive capture,
// deferred photo delivery, and fast capture prioritization.

@preconcurrency import AVFoundation
import ImageIO
import UIKit

enum CaptureEngineError: Error {
    case cameraUnavailable
    case configurationFailed
}

enum CaptureEvent: Sendable {
    /// The shutter fired; processed data arrives later via `.captured`.
    case willCapture
    case captured(CapturedAsset)
}

struct CapturedAsset: Sendable {
    let id: UUID
    /// Compressed photo container data, ready for the photo library as-is.
    let fileData: Data
    /// Small embedded preview, used for the tumble animation and quality scoring.
    let preview: UIImage?
    /// True when `fileData` is a deferred photo proxy that Photos finishes processing.
    let isProxy: Bool
    let capturedAt: Date
}

protocol CaptureEngineProtocol: Sendable {
    func prewarm(_ configuration: CaptureConfiguration) async
    func start(_ configuration: CaptureConfiguration) async -> AsyncStream<CaptureEvent>
    func stop() async
}

actor CaptureEngine: CaptureEngineProtocol {
    // 24 MP default: the largest supported dimensions at or below this pixel
    // count are requested. 48 MP is deliberately not used (memory, file size).
    private static let maxPixelCount = 25_000_000

    // AVCaptureSession.startRunning() blocks for hundreds of milliseconds;
    // a dedicated queue as the actor's executor keeps that off the shared
    // cooperative pool (the classic "session queue", with actor isolation).
    private let executorQueue = DispatchSerialQueue(label: "com.trueframe.capture.engine")
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executorQueue.asUnownedSerialExecutor()
    }

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var configuredLens: BackCameraType?

    private var isRunning = false
    private var cadenceTask: Task<Void, Never>?
    private var continuation: AsyncStream<CaptureEvent>.Continuation?
    private var inFlightDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // MARK: - Public API

    func prewarm(_ configuration: CaptureConfiguration) async {
        guard (try? configureIfNeeded(configuration)) != nil else { return }
        if !session.isRunning { session.startRunning() }
        // Preallocate capture resources so the first shot isn't slowed by
        // allocation. The actual capture uses a NEW, identically configured
        // settings object (prepared settings can't be reused).
        photoOutput.setPreparedPhotoSettingsArray([makePhotoSettings(configuration)], completionHandler: nil)
    }

    func start(_ configuration: CaptureConfiguration) -> AsyncStream<CaptureEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.continuation?.finish()
        self.continuation = continuation
        isRunning = true
        cadenceTask = Task { await runCadence(configuration) }
        return stream
    }

    func stop() async {
        isRunning = false
        cadenceTask?.cancel()
        cadenceTask = nil

        // Drain in-flight captures so their events reach the stream, bounded at 2s.
        for _ in 0..<80 where !inFlightDelegates.isEmpty {
            try? await Task.sleep(for: .milliseconds(25))
        }

        continuation?.finish()
        continuation = nil
        // The session keeps running so the next session starts instantly;
        // prewarm() is called again when the app returns to idle.
    }

    // MARK: - Session Configuration

    private func configureIfNeeded(_ configuration: CaptureConfiguration) throws {
        guard configuredLens != configuration.lens else { return }

        guard let camera = backCamera(for: configuration.lens) else {
            throw CaptureEngineError.cameraUnavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo  // the only preset supporting 24/48 MP

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureEngineError.configurationFailed }
        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw CaptureEngineError.configurationFailed }
            session.addOutput(photoOutput)
        }

        // All output configuration happens before commitConfiguration();
        // changing it later triggers an expensive pipeline rebuild.
        photoOutput.maxPhotoDimensions = Self.targetDimensions(for: camera)
        photoOutput.maxPhotoQualityPrioritization = .quality
        if photoOutput.isResponsiveCaptureSupported { photoOutput.isResponsiveCaptureEnabled = true }
        if photoOutput.isAutoDeferredPhotoDeliverySupported { photoOutput.isAutoDeferredPhotoDeliveryEnabled = true }
        if photoOutput.isFastCapturePrioritizationSupported { photoOutput.isFastCapturePrioritizationEnabled = true }
        if photoOutput.isZeroShutterLagSupported { photoOutput.isZeroShutterLagEnabled = true }

        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90  // portrait
        }

        if camera.isFocusModeSupported(.continuousAutoFocus) {
            try? camera.lockForConfiguration()
            camera.focusMode = .continuousAutoFocus
            camera.automaticallyAdjustsFaceDrivenAutoFocusEnabled = true
            camera.unlockForConfiguration()
        }

        configuredLens = configuration.lens
    }

    private func backCamera(for lens: BackCameraType) -> AVCaptureDevice? {
        let deviceType: AVCaptureDevice.DeviceType
        switch lens {
        case .wide: deviceType = .builtInWideAngleCamera
        case .ultrawide: deviceType = .builtInUltraWideCamera
        case .telephoto: deviceType = .builtInTelephotoCamera
        }
        return AVCaptureDevice.default(deviceType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private static func targetDimensions(for camera: AVCaptureDevice) -> CMVideoDimensions {
        let supported = camera.activeFormat.supportedMaxPhotoDimensions
        let area: (CMVideoDimensions) -> Int = { Int($0.width) * Int($0.height) }
        let within = supported.filter { area($0) <= maxPixelCount }
        let pick = within.max { area($0) < area($1) } ?? supported.max { area($0) < area($1) }
        return pick ?? CMVideoDimensions(width: 4032, height: 3024)
    }

    // MARK: - Cadence

    private func runCadence(_ configuration: CaptureConfiguration) async {
        do {
            try configureIfNeeded(configuration)
        } catch {
            print("[CaptureEngine] Configuration failed: \(error)")
            isRunning = false
            continuation?.finish()
            return
        }
        if !session.isRunning { session.startRunning() }

        while isRunning && !Task.isCancelled {
            await waitUntilReadyForCapture()
            guard isRunning && !Task.isCancelled else { break }
            captureOne(configuration)
            // The interval is the floor; readiness gating above stretches the
            // effective cadence when the hardware can't keep up.
            try? await Task.sleep(for: .seconds(configuration.interval))
        }
    }

    private func waitUntilReadyForCapture() async {
        while isRunning && photoOutput.captureReadiness != .ready {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func captureOne(_ configuration: CaptureConfiguration) {
        let settings = makePhotoSettings(configuration)
        let delegate = PhotoCaptureDelegate(engine: self, captureID: settings.uniqueID)
        inFlightDelegates[settings.uniqueID] = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func makePhotoSettings(_ configuration: CaptureConfiguration) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        settings.photoQualityPrioritization = .quality

        if configuration.resolvedFlashEnabled, photoOutput.supportedFlashModes.contains(.on) {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }

        if let previewFormat = settings.availablePreviewPhotoPixelFormatTypes.first {
            settings.previewPhotoFormat = [
                kCVPixelBufferPixelFormatTypeKey as String: previewFormat,
                kCVPixelBufferWidthKey as String: 512,
                kCVPixelBufferHeightKey as String: 512,
            ]
        }

        return settings
    }

    // MARK: - Delegate Callbacks

    fileprivate func handleWillCapture() {
        continuation?.yield(.willCapture)
    }

    fileprivate func handleCaptured(_ asset: CapturedAsset) {
        continuation?.yield(.captured(asset))
    }

    fileprivate func handleFinished(captureID: Int64) {
        inFlightDelegates[captureID] = nil
    }
}

// MARK: - Per-Capture Delegate

// One short-lived delegate per shot; the engine retains it until
// didFinishCaptureFor. All stored state is immutable, so crossing from the
// engine actor to AVFoundation's callback queue is safe.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let engine: CaptureEngine
    private let captureID: Int64

    init(engine: CaptureEngine, captureID: Int64) {
        self.engine = engine
        self.captureID = captureID
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let engine = engine
        Task { await engine.handleWillCapture() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        deliver(photo: deferredPhotoProxy, isProxy: true, error: error)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        deliver(photo: photo, isProxy: false, error: error)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let engine = engine
        let id = captureID
        Task { await engine.handleFinished(captureID: id) }
    }

    private func deliver(photo: AVCapturePhoto?, isProxy: Bool, error: Error?) {
        if let error {
            print("[CaptureEngine] Capture failed: \(error)")
            return
        }
        // Extract data synchronously in the callback while buffers are valid.
        guard let photo, let data = photo.fileDataRepresentation() else { return }
        let asset = CapturedAsset(
            id: UUID(),
            fileData: data,
            preview: photo.previewUIImage,
            isProxy: isProxy,
            capturedAt: Date()
        )
        let engine = engine
        Task { await engine.handleCaptured(asset) }
    }
}

private extension AVCapturePhoto {
    var previewUIImage: UIImage? {
        guard let cgImage = previewCGImageRepresentation() else { return nil }
        var orientation = UIImage.Orientation.up
        if let raw = metadata[String(kCGImagePropertyOrientation)] as? UInt32,
           let cgOrientation = CGImagePropertyOrientation(rawValue: raw) {
            orientation = UIImage.Orientation(cgOrientation)
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}

private extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
