// Video recording service for proximity-triggered video capture.
// Records video when phone is held to heart, similar to photo capture.

@preconcurrency import AVFoundation
import Photos
import UIKit

/// Errors that can occur during video recording
enum VideoRecordingError: Error, LocalizedError {
    case notConfigured
    case recordingInProgress
    case deviceNotAvailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Video recording not configured"
        case .recordingInProgress: return "A recording is already in progress"
        case .deviceNotAvailable: return "Camera device not available"
        case .saveFailed: return "Failed to save video"
        }
    }
}

/// Video quality preset
enum VideoQuality: String, CaseIterable, Identifiable {
    case high4K = "4K"
    case fullHD = "1080p"
    case hd = "720p"

    var id: String { rawValue }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .high4K: return .hd4K3840x2160
        case .fullHD: return .hd1920x1080
        case .hd: return .hd1280x720
        }
    }
}

/// Configuration for video recording
struct VideoConfiguration: Sendable {
    let quality: VideoQuality
    let maxDuration: TimeInterval
    let enableAudio: Bool
    let stabilizationMode: AVCaptureVideoStabilizationMode

    static let `default` = VideoConfiguration(
        quality: .fullHD,
        maxDuration: 60.0,
        enableAudio: true,
        stabilizationMode: .auto
    )

    static let highQuality = VideoConfiguration(
        quality: .high4K,
        maxDuration: 30.0,
        enableAudio: true,
        stabilizationMode: .cinematic
    )
}

/// Video recording service with proximity trigger support
actor VideoRecordingService {
    // MARK: - Shared Instance

    static let shared = VideoRecordingService()

    // MARK: - Properties

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoInput: AVCaptureDeviceInput?

    private var isRecording = false
    private var configuration: VideoConfiguration = .default
    private var currentOutputURL: URL?

    private weak var delegate: VideoRecordingDelegate?

    /// Continuation waiting for recording to finish (for stopRecording to wait)
    private var stopContinuation: CheckedContinuation<URL?, Never>?

    private let sessionQueue = DispatchQueue(label: "com.trueframe.video.session", qos: .userInitiated)
    private let tempDirectory: URL

    // MARK: - Delegate Wrapper

    private var delegateWrapper: VideoFileOutputDelegate?

    // MARK: - Initialization

    init() {
        // Safely get cache directory
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            tempDirectory = caches.appendingPathComponent("VideoRecordings", isDirectory: true)
        } else {
            // Fallback to temp directory
            tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("VideoRecordings")
        }
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Configuration

    func configure(with config: VideoConfiguration) async throws {
        // Clean up any existing session first and wait for it
        await tearDown()

        // Additional delay to ensure camera is fully released
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        self.configuration = config

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Set quality preset - fall back gracefully
        if session.canSetSessionPreset(config.quality.sessionPreset) {
            session.sessionPreset = config.quality.sessionPreset
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw VideoRecordingError.deviceNotAvailable
        }

        let videoIn: AVCaptureDeviceInput
        do {
            videoIn = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            session.commitConfiguration()
            print("[VideoRecording] Failed to create video input: \(error)")
            throw VideoRecordingError.notConfigured
        }

        guard session.canAddInput(videoIn) else {
            session.commitConfiguration()
            throw VideoRecordingError.notConfigured
        }
        session.addInput(videoIn)
        self.videoInput = videoIn

        // Add audio input if enabled (optional, don't fail if unavailable)
        if config.enableAudio {
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let audioIn = try AVCaptureDeviceInput(device: audioDevice)
                    if session.canAddInput(audioIn) {
                        session.addInput(audioIn)
                        self.audioInput = audioIn
                    }
                } catch {
                    print("[VideoRecording] Audio input unavailable: \(error)")
                    // Continue without audio
                }
            }
        }

        // Add movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.maxRecordedDuration = CMTime(seconds: config.maxDuration, preferredTimescale: 600)

        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            throw VideoRecordingError.notConfigured
        }
        session.addOutput(movieOutput)

        // Configure stabilization
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = config.stabilizationMode
            }
        }

        session.commitConfiguration()

        self.captureSession = session
        self.videoOutput = movieOutput
        self.delegateWrapper = VideoFileOutputDelegate(service: self)
    }

    func setDelegate(_ delegate: VideoRecordingDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        // Check configuration first
        guard let output = videoOutput else {
            throw VideoRecordingError.notConfigured
        }
        guard !isRecording else {
            throw VideoRecordingError.recordingInProgress
        }
        guard let delegateWrapper else {
            throw VideoRecordingError.notConfigured
        }
        guard let session = captureSession else {
            throw VideoRecordingError.notConfigured
        }

        // Create output URL
        let fileName = "trueframe-video-\(UUID().uuidString.prefix(8)).mov"
        let outputURL = tempDirectory.appendingPathComponent(fileName)
        currentOutputURL = outputURL

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Start session and recording on the session queue
        let capturedOutput = output
        let capturedDelegate = delegateWrapper
        let capturedURL = outputURL

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                // Start recording on the session queue where AVFoundation expects it
                capturedOutput.startRecording(to: capturedURL, recordingDelegate: capturedDelegate)
                continuation.resume()
            }
        }

        // Brief pause to let recording stabilize
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        isRecording = true

        // Notify delegate
        let videoDelegate = delegate
        Task { @MainActor in
            videoDelegate?.videoRecording(didStartAt: outputURL)
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording, let output = videoOutput else { return nil }

        isRecording = false

        // Wait for the file to be finalized via delegate callback
        let url = await withCheckedContinuation { continuation in
            stopContinuation = continuation
            output.stopRecording()
        }

        return url
    }

    // MARK: - File Output Handling

    func handleRecordingFinished(at outputURL: URL, error: Error?) {
        isRecording = false

        // Resume any waiting stopRecording() call with the finalized URL
        if let continuation = stopContinuation {
            stopContinuation = nil
            continuation.resume(returning: error == nil ? outputURL : nil)
        }

        let videoDelegate = delegate
        if let error = error {
            Task { @MainActor in
                videoDelegate?.videoRecording(didFailWithError: error)
            }
            return
        }

        Task { @MainActor in
            videoDelegate?.videoRecording(didFinishAt: outputURL)
        }
    }

    // MARK: - Save to Library

    func saveToPhotoLibrary(_ videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VideoRecordingError.saveFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: videoURL, options: nil)
            request.creationDate = Date()
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: videoURL)
    }

    // MARK: - Status

    var recordingDuration: TimeInterval {
        guard isRecording, let output = videoOutput else { return 0 }
        return CMTimeGetSeconds(output.recordedDuration)
    }

    var recordingFileSize: Int64 {
        guard isRecording, let output = videoOutput else { return 0 }
        return output.recordedFileSize
    }

    // MARK: - Cleanup

    func tearDown() async {
        // Save state before clearing
        let wasRecording = isRecording
        isRecording = false

        let session = captureSession
        let output = videoOutput

        // Cancel any pending stop continuation
        if let continuation = stopContinuation {
            stopContinuation = nil
            continuation.resume(returning: nil)
        }

        // Stop recording first if in progress (triggers delegate callback)
        if wasRecording, let output = output, output.isRecording {
            output.stopRecording()
        }

        // Stop session and wait for it to complete
        if let session = session {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                sessionQueue.async {
                    session.stopRunning()
                    continuation.resume()
                }
            }
        }

        // If we were recording, wait for delegate callback to complete
        // This prevents crash from callback on deallocated delegate
        if wasRecording {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }

        // Now safe to clear references (delegate callback has fired)
        captureSession = nil
        videoOutput = nil
        videoInput = nil
        audioInput = nil
        delegateWrapper = nil
    }

    nonisolated func clearCache() {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Video Recording Delegate

/// Protocol for video recording callbacks - NOT MainActor to allow flexible implementations
protocol VideoRecordingDelegate: AnyObject, Sendable {
    @MainActor func videoRecording(didStartAt url: URL)
    @MainActor func videoRecording(didFinishAt url: URL)
    @MainActor func videoRecording(didUpdateDuration duration: TimeInterval)
    @MainActor func videoRecording(didFailWithError error: Error)
}

// MARK: - File Output Delegate Wrapper

private final class VideoFileOutputDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private weak var service: VideoRecordingService?

    init(service: VideoRecordingService) {
        self.service = service
        super.init()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started - nothing to do here
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Capture values synchronously before async boundary
        let url = outputFileURL
        let capturedError = error
        let serviceRef = service

        Task {
            await serviceRef?.handleRecordingFinished(at: url, error: capturedError)
        }
    }
}
