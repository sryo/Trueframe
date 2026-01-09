// Mock implementation of CameraService for unit testing.

import AVFoundation
import Combine
import UIKit
@testable import Trueframe

/// A mock camera service that simulates camera behavior for testing.
/// Allows fine-grained control over capture timing, errors, and responses.
final class MockCameraService: CameraServiceProtocol {

    // MARK: - Published State

    private let capturedPhotoSubject = PassthroughSubject<CapturedPhoto, Never>()
    var capturedPhoto: AnyPublisher<CapturedPhoto, Never> {
        capturedPhotoSubject.eraseToAnyPublisher()
    }

    private(set) var isReady = false
    private(set) var flashEnabled = false

    // MARK: - Tracking Properties (for test assertions)

    var preWarmCallCount = 0
    var configureCallCount = 0
    var capturePhotoCallCount = 0
    var captureReactionShotCallCount = 0
    var tearDownCallCount = 0
    var updateSettingsCallCount = 0

    var lastConfiguredPosition: CameraPosition?
    var lastSettingsUpdate: (wide: Bool, ultrawide: Bool, telephoto: Bool, flash: Bool)?

    // MARK: - Configuration for Test Scenarios

    var shouldFailConfiguration = false
    var configurationError: CameraError = .configurationFailed
    var shouldFailCapture = false
    var captureError: CameraError = .photoProcessingFailed
    var captureDelay: TimeInterval = 0

    /// Photos to emit when capturePhoto is called
    var photosToEmit: [CapturedPhoto] = []
    private var photoEmitIndex = 0

    // MARK: - Protocol Implementation

    func preWarm() {
        preWarmCallCount += 1
        isReady = true
    }

    func configure(for position: CameraPosition) async throws {
        configureCallCount += 1
        lastConfiguredPosition = position

        if shouldFailConfiguration {
            throw configurationError
        }

        isReady = true
    }

    func capturePhoto() async throws {
        capturePhotoCallCount += 1

        if captureDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(captureDelay * 1_000_000_000))
        }

        if shouldFailCapture {
            throw captureError
        }

        // Emit next photo if available
        if photoEmitIndex < photosToEmit.count {
            let photo = photosToEmit[photoEmitIndex]
            photoEmitIndex += 1
            capturedPhotoSubject.send(photo)
        }
    }

    func captureReactionShot() async throws {
        captureReactionShotCallCount += 1

        if shouldFailCapture {
            throw captureError
        }
    }

    func updateCameraSettings(wide: Bool, ultrawide: Bool, telephoto: Bool, flash: Bool) {
        updateSettingsCallCount += 1
        lastSettingsUpdate = (wide, ultrawide, telephoto, flash)
        flashEnabled = flash
    }

    func tearDown() {
        tearDownCallCount += 1
        isReady = false
    }

    // MARK: - Test Helpers

    /// Reset all tracking counters and state
    func reset() {
        preWarmCallCount = 0
        configureCallCount = 0
        capturePhotoCallCount = 0
        captureReactionShotCallCount = 0
        tearDownCallCount = 0
        updateSettingsCallCount = 0
        lastConfiguredPosition = nil
        lastSettingsUpdate = nil
        shouldFailConfiguration = false
        shouldFailCapture = false
        captureDelay = 0
        photosToEmit = []
        photoEmitIndex = 0
        isReady = false
        flashEnabled = false
    }

    /// Manually emit a captured photo (simulating camera capture)
    func emitPhoto(_ photo: CapturedPhoto) {
        capturedPhotoSubject.send(photo)
    }

    /// Create a test image with specified brightness
    static func createTestImage(brightness: CGFloat = 0.5, size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: brightness, alpha: 1.0).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Create a test CapturedPhoto
    static func createTestPhoto(brightness: CGFloat = 0.5) -> CapturedPhoto {
        CapturedPhoto(image: createTestImage(brightness: brightness))
    }

    /// Create a pitch black photo (simulating pocket capture)
    static func createDarkPhoto() -> CapturedPhoto {
        CapturedPhoto(image: createTestImage(brightness: 0.02))
    }
}
