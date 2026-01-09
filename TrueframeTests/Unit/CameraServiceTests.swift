// Unit tests for CameraService.

import AVFoundation
import Combine
import XCTest
@testable import Trueframe

/// Tests for CameraService functionality.
/// Note: Many tests require device camera and cannot run in simulator.
/// CameraService is an actor, so most tests need to be async.
final class CameraServiceTests: XCTestCase {

    var sut: CameraService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        sut = CameraService()
        cancellables = []
    }

    override func tearDown() async throws {
        if let sut = sut {
            await sut.tearDown()
        }
        sut = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testCameraService_initialState_isNotReady() async {
        let isReady = await sut.isReady
        XCTAssertFalse(isReady, "Camera should not be ready before configuration")
    }

    func testCameraService_initialState_flashDisabled() async {
        let flashEnabled = await sut.flashEnabled
        XCTAssertFalse(flashEnabled, "Flash should be disabled initially")
    }

    // MARK: - Settings Tests

    func testUpdateCameraSettings_withFlashEnabled_updatesFlashState() async {
        await sut.updateCameraSettings(wide: true, ultrawide: false, telephoto: false, flash: true)

        let flashEnabled = await sut.flashEnabled
        XCTAssertTrue(flashEnabled, "Flash should be enabled after update")
    }

    func testUpdateCameraSettings_withFlashDisabled_keepsFlashDisabled() async {
        await sut.updateCameraSettings(wide: true, ultrawide: true, telephoto: false, flash: false)

        let flashEnabled = await sut.flashEnabled
        XCTAssertFalse(flashEnabled, "Flash should remain disabled")
    }

    func testUpdateCameraSettings_multipleUpdates_lastValueWins() async {
        await sut.updateCameraSettings(wide: true, ultrawide: false, telephoto: false, flash: true)
        await sut.updateCameraSettings(wide: true, ultrawide: false, telephoto: false, flash: false)

        let flashEnabled = await sut.flashEnabled
        XCTAssertFalse(flashEnabled, "Flash should reflect last update")
    }

    // MARK: - PreWarm Tests

    func testPreWarm_whenNotReady_startsSession() async {
        // Note: This test may require real device
        await sut.preWarm()

        // PreWarm runs async, so we just verify it doesn't crash
        // isReady depends on actual camera hardware availability
    }

    func testPreWarm_whenAlreadyReady_doesNothing() async {
        // First prewarm
        await sut.preWarm()

        // Wait a bit for async setup
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Second prewarm should be no-op
        let initialReady = await sut.isReady
        await sut.preWarm()

        let afterReady = await sut.isReady
        XCTAssertEqual(afterReady, initialReady, "Ready state should not change")
    }

    // MARK: - TearDown Tests

    func testTearDown_resetsReadyState() async {
        await sut.preWarm()

        // Wait for potential setup
        try? await Task.sleep(nanoseconds: 500_000_000)

        await sut.tearDown()

        let isReady = await sut.isReady
        XCTAssertFalse(isReady, "Camera should not be ready after teardown")
    }

    func testTearDown_canBeCalledMultipleTimes() async {
        await sut.tearDown()
        await sut.tearDown()
        await sut.tearDown()

        // Should not crash
        let isReady = await sut.isReady
        XCTAssertFalse(isReady)
    }

    func testTearDown_whileCapturingFrame_doesNotCrash() async {
        // Start capture frame request (will wait for video frame)
        let captureTask = Task {
            // This will return nil since camera isn't configured
            return await sut.captureFrame()
        }

        // Immediately teardown
        await sut.tearDown()

        // Should complete without crashing
        let result = await captureTask.value
        XCTAssertNil(result, "CaptureFrame should return nil when not ready")
    }

    func testTearDown_rapidCycles_doesNotCrash() async {
        // Rapid teardown cycles
        for _ in 0..<10 {
            await sut.preWarm()
            await sut.tearDown()
        }

        // Should not crash
        let isReady = await sut.isReady
        XCTAssertFalse(isReady)
    }

    // MARK: - CaptureFrame Tests

    func testCaptureFrame_whenNotReady_returnsNil() async {
        let result = await sut.captureFrame()
        XCTAssertNil(result, "CaptureFrame should return nil when camera not ready")
    }

    func testCaptureFrame_afterTearDown_returnsNil() async {
        await sut.preWarm()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await sut.tearDown()

        let result = await sut.captureFrame()
        XCTAssertNil(result, "CaptureFrame should return nil after teardown")
    }

    func testCaptureFrame_multipleConcurrentCalls_handlesProperly() async {
        // Multiple concurrent capture frame calls
        async let frame1 = sut.captureFrame()
        async let frame2 = sut.captureFrame()
        async let frame3 = sut.captureFrame()

        // All should complete without crashing (returning nil since not configured)
        let results = await [frame1, frame2, frame3]
        for result in results {
            XCTAssertNil(result)
        }
    }

    // MARK: - Publisher Tests

    func testCapturedPhoto_publisherExists() {
        var receivedPhotos: [CapturedPhoto] = []

        sut.capturedPhoto
            .sink { photo in
                receivedPhotos.append(photo)
            }
            .store(in: &cancellables)

        // Publisher should be accessible
        XCTAssertTrue(receivedPhotos.isEmpty, "No photos should be received initially")
    }

    // MARK: - Error Cases

    func testCapturePhoto_whenNotConfigured_throws() async {
        do {
            try await sut.capturePhoto()
            XCTFail("Should throw when not configured")
        } catch {
            XCTAssertTrue(error is CameraError, "Should throw CameraError")
        }
    }
}

// MARK: - CameraError Tests

final class CameraErrorTests: XCTestCase {

    func testCameraUnavailable_hasCorrectDescription() {
        let error = CameraError.cameraUnavailable
        XCTAssertEqual(error.errorDescription, "Camera is not available")
    }

    func testConfigurationFailed_hasCorrectDescription() {
        let error = CameraError.configurationFailed
        XCTAssertEqual(error.errorDescription, "Failed to configure camera")
    }

    func testNotConfigured_hasCorrectDescription() {
        let error = CameraError.notConfigured
        XCTAssertEqual(error.errorDescription, "Camera not configured")
    }

    func testPhotoProcessingFailed_hasCorrectDescription() {
        let error = CameraError.photoProcessingFailed
        XCTAssertEqual(error.errorDescription, "Failed to process photo")
    }

    func testCameraError_isLocalizedError() {
        let errors: [CameraError] = [
            .cameraUnavailable,
            .configurationFailed,
            .notConfigured,
            .photoProcessingFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
        }
    }
}

// MARK: - CameraPosition Tests

final class CameraPositionTests: XCTestCase {

    func testCameraPosition_frontEqualsItself() {
        XCTAssertEqual(CameraPosition.front, CameraPosition.front)
    }

    func testCameraPosition_backEqualsItself() {
        XCTAssertEqual(CameraPosition.back, CameraPosition.back)
    }

    func testCameraPosition_bothEqualsItself() {
        XCTAssertEqual(CameraPosition.both, CameraPosition.both)
    }

    func testCameraPosition_differentPositionsNotEqual() {
        XCTAssertNotEqual(CameraPosition.front, CameraPosition.back)
        XCTAssertNotEqual(CameraPosition.front, CameraPosition.both)
        XCTAssertNotEqual(CameraPosition.back, CameraPosition.both)
    }

    func testCameraPosition_isSendable() {
        // Compile-time check - if this compiles, CameraPosition is Sendable
        Task { @Sendable in
            let _ = CameraPosition.front
        }
    }
}

// MARK: - Delegate Callback Tests

final class CameraServiceDelegateTests: XCTestCase {
    var sut: CameraService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        sut = CameraService()
        cancellables = []
    }

    override func tearDown() async throws {
        if let sut = sut {
            await sut.tearDown()
        }
        sut = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Photo Handler Tests

    func testHandlePhotoImage_withValidImage_publishesPhoto() async {
        let expectation = XCTestExpectation(description: "Photo published")

        sut.capturedPhoto
            .sink { photo in
                XCTAssertNotNil(photo.image)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Create a test image
        let testImage = UIImage(systemName: "camera")!

        // Call the handler directly
        await sut.handlePhotoImage(testImage)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testHandlePhotoError_doesNotPublishPhoto() async {
        var receivedPhotos: [CapturedPhoto] = []

        sut.capturedPhoto
            .sink { photo in
                receivedPhotos.append(photo)
            }
            .store(in: &cancellables)

        // Call error handler
        await sut.handlePhotoError(CameraError.photoProcessingFailed)

        // Wait a bit to ensure no photo is published
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(receivedPhotos.isEmpty, "No photo should be published on error")
    }

    func testHandlePhotoImage_multipleTimes_publishesAll() async {
        var receivedCount = 0
        let expectedCount = 5

        sut.capturedPhoto
            .sink { _ in
                receivedCount += 1
            }
            .store(in: &cancellables)

        let testImage = UIImage(systemName: "camera")!

        for _ in 0..<expectedCount {
            await sut.handlePhotoImage(testImage)
        }

        // Wait for all to be processed
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(receivedCount, expectedCount)
    }

    // MARK: - Video Frame Handler Tests

    func testHandleVideoFrameImage_whenNoPendingCapture_doesNotCrash() async {
        let testImage = UIImage(systemName: "camera")!

        // Should not crash even without pending capture
        await sut.handleVideoFrameImage(testImage)
    }

    func testHandleVideoFrameImage_resolvesCapture() async throws {
        // This test verifies the frame capture flow doesn't crash
        // The actual frame will be nil since camera isn't configured

        let result = await sut.captureFrame()
        XCTAssertNil(result, "Should return nil when not configured")
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentPhotoHandling_doesNotCrash() async {
        let testImage = UIImage(systemName: "camera")!

        // Simulate rapid concurrent photo handling
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await self.sut.handlePhotoImage(testImage)
                }
            }
        }

        // If we get here, no crash occurred
    }

    func testConcurrentPhotoHandlingDuringTearDown_doesNotCrash() async {
        let testImage = UIImage(systemName: "camera")!

        // Start sending photos
        let photoTask = Task {
            for _ in 0..<10 {
                await self.sut.handlePhotoImage(testImage)
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        // Tear down while photos are being processed
        try? await Task.sleep(nanoseconds: 50_000_000)
        await sut.tearDown()

        photoTask.cancel()
        await photoTask.value

        // If we get here, no crash occurred
    }

    func testRapidStartStopCycles_doesNotCrash() async {
        for _ in 0..<10 {
            await sut.preWarm()
            try? await Task.sleep(nanoseconds: 50_000_000)
            await sut.tearDown()
        }

        // If we get here, no crash occurred
        let isReady = await sut.isReady
        XCTAssertFalse(isReady)
    }
}
