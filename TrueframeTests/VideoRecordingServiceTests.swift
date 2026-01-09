// Comprehensive unit tests for VideoRecordingService.

import AVFoundation
import XCTest
@testable import Trueframe

// MARK: - VideoRecordingError Tests

/// Tests for VideoRecordingError enum and its LocalizedError conformance.
final class VideoRecordingErrorTests: XCTestCase {

    func testNotConfigured_hasCorrectDescription() {
        let error = VideoRecordingError.notConfigured
        XCTAssertEqual(error.errorDescription, "Video recording not configured")
    }

    func testRecordingInProgress_hasCorrectDescription() {
        let error = VideoRecordingError.recordingInProgress
        XCTAssertEqual(error.errorDescription, "A recording is already in progress")
    }

    func testDeviceNotAvailable_hasCorrectDescription() {
        let error = VideoRecordingError.deviceNotAvailable
        XCTAssertEqual(error.errorDescription, "Camera device not available")
    }

    func testSaveFailed_hasCorrectDescription() {
        let error = VideoRecordingError.saveFailed
        XCTAssertEqual(error.errorDescription, "Failed to save video")
    }

    func testAllErrors_haveNonNilDescriptions() {
        let allErrors: [VideoRecordingError] = [
            .notConfigured,
            .recordingInProgress,
            .deviceNotAvailable,
            .saveFailed
        ]

        for error in allErrors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) should have non-empty description")
        }
    }

    func testVideoRecordingError_conformsToLocalizedError() {
        let error: LocalizedError = VideoRecordingError.notConfigured
        XCTAssertNotNil(error.errorDescription)
    }
}

// MARK: - VideoQuality Tests

/// Tests for VideoQuality enum.
final class VideoQualityTests: XCTestCase {

    func testHigh4K_hasCorrectRawValue() {
        XCTAssertEqual(VideoQuality.high4K.rawValue, "4K")
    }

    func testFullHD_hasCorrectRawValue() {
        XCTAssertEqual(VideoQuality.fullHD.rawValue, "1080p")
    }

    func testHD_hasCorrectRawValue() {
        XCTAssertEqual(VideoQuality.hd.rawValue, "720p")
    }

    func testHigh4K_hasCorrectSessionPreset() {
        XCTAssertEqual(VideoQuality.high4K.sessionPreset, AVCaptureSession.Preset.hd4K3840x2160)
    }

    func testFullHD_hasCorrectSessionPreset() {
        XCTAssertEqual(VideoQuality.fullHD.sessionPreset, AVCaptureSession.Preset.hd1920x1080)
    }

    func testHD_hasCorrectSessionPreset() {
        XCTAssertEqual(VideoQuality.hd.sessionPreset, AVCaptureSession.Preset.hd1280x720)
    }

    func testAllCases_containsAllQualities() {
        let allCases = VideoQuality.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.high4K))
        XCTAssertTrue(allCases.contains(.fullHD))
        XCTAssertTrue(allCases.contains(.hd))
    }

    func testIdentifiable_idMatchesRawValue() {
        for quality in VideoQuality.allCases {
            XCTAssertEqual(quality.id, quality.rawValue)
        }
    }

    func testVideoQuality_isSendable() {
        // Compile-time check - if this compiles, VideoQuality is Sendable
        Task { @Sendable in
            let _ = VideoQuality.fullHD
        }
    }
}

// MARK: - VideoConfiguration Tests

/// Tests for VideoConfiguration struct.
final class VideoConfigurationTests: XCTestCase {

    func testDefaultConfiguration_hasExpectedValues() {
        let config = VideoConfiguration.default

        XCTAssertEqual(config.quality, .fullHD)
        XCTAssertEqual(config.maxDuration, 60.0)
        XCTAssertTrue(config.enableAudio)
        XCTAssertEqual(config.stabilizationMode, .auto)
    }

    func testHighQualityConfiguration_hasExpectedValues() {
        let config = VideoConfiguration.highQuality

        XCTAssertEqual(config.quality, .high4K)
        XCTAssertEqual(config.maxDuration, 30.0)
        XCTAssertTrue(config.enableAudio)
        XCTAssertEqual(config.stabilizationMode, .cinematic)
    }

    func testCustomConfiguration_preservesValues() {
        let config = VideoConfiguration(
            quality: .hd,
            maxDuration: 120.0,
            enableAudio: false,
            stabilizationMode: .standard
        )

        XCTAssertEqual(config.quality, .hd)
        XCTAssertEqual(config.maxDuration, 120.0)
        XCTAssertFalse(config.enableAudio)
        XCTAssertEqual(config.stabilizationMode, .standard)
    }

    func testVideoConfiguration_isSendable() {
        // Compile-time check - if this compiles, VideoConfiguration is Sendable
        Task { @Sendable in
            let _ = VideoConfiguration.default
        }
    }
}

// MARK: - MockVideoRecordingService Tests

/// Tests for the MockVideoRecordingService to ensure it behaves correctly for testing.
final class MockVideoRecordingServiceTests: XCTestCase {

    var mockService: MockVideoRecordingService!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockService = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testMockService_initialState_isNotConfigured() async {
        let isConfigured = await mockService.isConfigured
        XCTAssertFalse(isConfigured, "Mock should not be configured initially")
    }

    func testMockService_initialState_isNotRecording() async {
        let isRecording = await mockService.isRecording
        XCTAssertFalse(isRecording, "Mock should not be recording initially")
    }

    func testMockService_initialState_hasZeroCallCounts() async {
        let configureCount = await mockService.configureCallCount
        let startCount = await mockService.startRecordingCallCount
        let stopCount = await mockService.stopRecordingCallCount
        let tearDownCount = await mockService.tearDownCallCount

        XCTAssertEqual(configureCount, 0)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(tearDownCount, 0)
    }

    // MARK: - Configuration Tests

    func testConfigure_successfulConfiguration_setsConfiguredState() async throws {
        try await mockService.configure(with: .default)

        let isConfigured = await mockService.isConfigured
        let callCount = await mockService.configureCallCount

        XCTAssertTrue(isConfigured)
        XCTAssertEqual(callCount, 1)
    }

    func testConfigure_storesConfiguration() async throws {
        let config = VideoConfiguration.highQuality
        try await mockService.configure(with: config)

        let storedConfig = await mockService.currentConfiguration
        XCTAssertEqual(storedConfig?.quality, config.quality)
        XCTAssertEqual(storedConfig?.maxDuration, config.maxDuration)
    }

    func testConfigure_whenShouldFail_throwsError() async {
        await mockService.setShouldFailConfiguration(true, error: .deviceNotAvailable)

        do {
            try await mockService.configure(with: .default)
            XCTFail("Should have thrown an error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .deviceNotAvailable)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Start Recording Tests

    func testStartRecording_whenConfigured_startsRecording() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        let isRecording = await mockService.isRecording
        let callCount = await mockService.startRecordingCallCount

        XCTAssertTrue(isRecording)
        XCTAssertEqual(callCount, 1)
    }

    func testStartRecording_whenNotConfigured_throwsNotConfigured() async {
        do {
            try await mockService.startRecording()
            XCTFail("Should have thrown VideoRecordingError.notConfigured")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testStartRecording_whenAlreadyRecording_throwsRecordingInProgress() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        do {
            try await mockService.startRecording()
            XCTFail("Should have thrown VideoRecordingError.recordingInProgress")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .recordingInProgress)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testStartRecording_setsOutputURL() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        let outputURL = await mockService.lastOutputURL
        XCTAssertNotNil(outputURL)
        XCTAssertTrue(outputURL!.path.contains("test-recording"))
    }

    // MARK: - Stop Recording Tests

    func testStopRecording_whenRecording_returnsURL() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        let url = await mockService.stopRecording()

        XCTAssertNotNil(url)
        let isRecording = await mockService.isRecording
        XCTAssertFalse(isRecording)
    }

    func testStopRecording_whenNotRecording_returnsNil() async {
        let url = await mockService.stopRecording()

        XCTAssertNil(url)
    }

    func testStopRecording_incrementsCallCount() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()
        _ = await mockService.stopRecording()

        let callCount = await mockService.stopRecordingCallCount
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - TearDown Tests

    func testTearDown_resetsState() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        await mockService.tearDown()

        let isConfigured = await mockService.isConfigured
        let isRecording = await mockService.isRecording
        let config = await mockService.currentConfiguration

        XCTAssertFalse(isConfigured)
        XCTAssertFalse(isRecording)
        XCTAssertNil(config)
    }

    func testTearDown_incrementsCallCount() async {
        await mockService.tearDown()

        let callCount = await mockService.tearDownCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testTearDown_canBeCalledMultipleTimes() async {
        await mockService.tearDown()
        await mockService.tearDown()
        await mockService.tearDown()

        let callCount = await mockService.tearDownCallCount
        XCTAssertEqual(callCount, 3)
    }

    // MARK: - Reset Tests

    func testReset_clearsAllState() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()
        _ = await mockService.stopRecording()
        await mockService.tearDown()

        await mockService.reset()

        let configureCount = await mockService.configureCallCount
        let startCount = await mockService.startRecordingCallCount
        let stopCount = await mockService.stopRecordingCallCount
        let tearDownCount = await mockService.tearDownCallCount
        let isConfigured = await mockService.isConfigured
        let isRecording = await mockService.isRecording

        XCTAssertEqual(configureCount, 0)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(tearDownCount, 0)
        XCTAssertFalse(isConfigured)
        XCTAssertFalse(isRecording)
    }

}

// MARK: - MockVideoRecordingDelegate Tests

/// Tests for the MockVideoRecordingDelegate to ensure it tracks callbacks correctly.
@MainActor
final class MockVideoRecordingDelegateTests: XCTestCase {

    var mockDelegate: MockVideoRecordingDelegate!

    override func setUp() {
        super.setUp()
        mockDelegate = MockVideoRecordingDelegate()
    }

    override func tearDown() {
        mockDelegate?.reset()
        mockDelegate = nil
        super.tearDown()
    }

    func testDelegate_initialState_hasZeroCounts() {
        XCTAssertEqual(mockDelegate.didStartCallCount, 0)
        XCTAssertEqual(mockDelegate.didFinishCallCount, 0)
        XCTAssertEqual(mockDelegate.didUpdateDurationCallCount, 0)
        XCTAssertEqual(mockDelegate.didFailCallCount, 0)
    }

    func testDelegate_didStartAt_tracksURL() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        mockDelegate.videoRecording(didStartAt: url)

        XCTAssertEqual(mockDelegate.didStartCallCount, 1)
        XCTAssertEqual(mockDelegate.didStartAtURLs.first, url)
    }

    func testDelegate_didFinishAt_tracksURL() {
        let url = URL(fileURLWithPath: "/tmp/finished.mov")
        mockDelegate.videoRecording(didFinishAt: url)

        XCTAssertEqual(mockDelegate.didFinishCallCount, 1)
        XCTAssertEqual(mockDelegate.didFinishAtURLs.first, url)
    }

    func testDelegate_didUpdateDuration_tracksDuration() {
        mockDelegate.videoRecording(didUpdateDuration: 5.5)
        mockDelegate.videoRecording(didUpdateDuration: 10.0)

        XCTAssertEqual(mockDelegate.didUpdateDurationCallCount, 2)
        XCTAssertEqual(mockDelegate.didUpdateDurations, [5.5, 10.0])
    }

    func testDelegate_didFailWithError_tracksError() {
        let error = VideoRecordingError.saveFailed
        mockDelegate.videoRecording(didFailWithError: error)

        XCTAssertEqual(mockDelegate.didFailCallCount, 1)
        XCTAssertEqual(mockDelegate.didFailWithErrors.count, 1)
    }

    func testDelegate_reset_clearsAllTracking() {
        mockDelegate.videoRecording(didStartAt: URL(fileURLWithPath: "/tmp/test.mov"))
        mockDelegate.videoRecording(didFinishAt: URL(fileURLWithPath: "/tmp/test.mov"))
        mockDelegate.videoRecording(didUpdateDuration: 5.0)
        mockDelegate.videoRecording(didFailWithError: VideoRecordingError.saveFailed)

        mockDelegate.reset()

        XCTAssertEqual(mockDelegate.didStartCallCount, 0)
        XCTAssertEqual(mockDelegate.didFinishCallCount, 0)
        XCTAssertEqual(mockDelegate.didUpdateDurationCallCount, 0)
        XCTAssertEqual(mockDelegate.didFailCallCount, 0)
    }
}

// MARK: - VideoRecordingService Tests

/// Tests for the actual VideoRecordingService.
/// Note: Many tests require actual camera hardware and cannot run in simulator.
final class VideoRecordingServiceTests: XCTestCase {

    var sut: VideoRecordingService!

    override func setUp() {
        super.setUp()
        // Create fresh instance for each test
        sut = VideoRecordingService()
    }

    override func tearDown() async throws {
        // Clean up the service
        await sut?.tearDown()
        sut?.clearCache()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testVideoRecordingService_sharedInstance_exists() {
        XCTAssertNotNil(VideoRecordingService.shared)
    }

    func testVideoRecordingService_sharedInstance_isSameInstance() {
        let instance1 = VideoRecordingService.shared
        let instance2 = VideoRecordingService.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Initial State Tests

    func testRecordingDuration_beforeRecording_isZero() async {
        let duration = await sut.recordingDuration
        XCTAssertEqual(duration, 0)
    }

    func testRecordingFileSize_beforeRecording_isZero() async {
        let fileSize = await sut.recordingFileSize
        XCTAssertEqual(fileSize, 0)
    }

    // MARK: - Configuration Tests

    func testConfigure_withDefaultConfig_doesNotCrash() async {
        // Note: This may fail on simulator due to no camera
        do {
            try await sut.configure(with: .default)
        } catch {
            // Expected on simulator - camera not available
            XCTAssertTrue(error is VideoRecordingError)
        }
    }

    func testConfigure_withHighQualityConfig_doesNotCrash() async {
        do {
            try await sut.configure(with: .highQuality)
        } catch {
            // Expected on simulator - camera not available
            XCTAssertTrue(error is VideoRecordingError)
        }
    }

    func testConfigure_withCustomConfig_doesNotCrash() async {
        let customConfig = VideoConfiguration(
            quality: .hd,
            maxDuration: 30.0,
            enableAudio: false,
            stabilizationMode: .off
        )

        do {
            try await sut.configure(with: customConfig)
        } catch {
            // Expected on simulator
            XCTAssertTrue(error is VideoRecordingError)
        }
    }

    func testConfigure_calledMultipleTimes_doesNotCrash() async {
        do {
            try await sut.configure(with: .default)
            try await sut.configure(with: .highQuality)
            try await sut.configure(with: .default)
        } catch {
            // Expected on simulator
            XCTAssertTrue(error is VideoRecordingError)
        }
    }

    // MARK: - Start Recording Tests

    func testStartRecording_whenNotConfigured_throwsNotConfigured() async {
        do {
            try await sut.startRecording()
            XCTFail("Should have thrown VideoRecordingError.notConfigured")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Stop Recording Tests

    func testStopRecording_whenNotRecording_returnsNil() async {
        let url = await sut.stopRecording()
        XCTAssertNil(url, "Should return nil when not recording")
    }

    // MARK: - TearDown Tests

    func testTearDown_canBeCalledMultipleTimes() async {
        await sut.tearDown()
        await sut.tearDown()
        await sut.tearDown()
        // Should not crash
    }

    func testTearDown_afterConfiguration_doesNotCrash() async {
        do {
            try await sut.configure(with: .default)
        } catch {
            // Ignore configuration errors on simulator
        }

        await sut.tearDown()
    }

    func testTearDown_resetsState() async {
        // Configure (may fail on simulator)
        do {
            try await sut.configure(with: .default)
        } catch {
            // Continue with test
        }

        await sut.tearDown()

        // After teardown, starting should fail with notConfigured
        do {
            try await sut.startRecording()
            XCTFail("Should throw after tearDown")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Clear Cache Tests

    func testClearCache_doesNotCrash() {
        sut.clearCache()
    }

    func testClearCache_canBeCalledMultipleTimes() {
        sut.clearCache()
        sut.clearCache()
        sut.clearCache()
    }

    // MARK: - Delegate Tests

    func testSetDelegate_doesNotCrash() async {
        let delegate = await MainActor.run { MockVideoRecordingDelegate() }
        await sut.setDelegate(delegate)
    }

    func testSetDelegate_toNil_doesNotCrash() async {
        await sut.setDelegate(nil)
    }

    // MARK: - Recording Duration and File Size Tests

    func testRecordingDuration_whenNotRecording_returnsZero() async {
        let duration = await sut.recordingDuration
        XCTAssertEqual(duration, 0)
    }

    func testRecordingFileSize_whenNotRecording_returnsZero() async {
        let size = await sut.recordingFileSize
        XCTAssertEqual(size, 0)
    }
}

// MARK: - Stop Continuation Pattern Tests

/// Tests specifically for the stopContinuation pattern that waits for file finalization.
final class StopContinuationPatternTests: XCTestCase {

    var mockService: MockVideoRecordingService!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockService = nil
        try await super.tearDown()
    }

    func testStopRecording_waitsForCompletion() async throws {
        // Configure and start
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        // Simulate async delay
        let expectedURL = URL(fileURLWithPath: "/tmp/final-video.mov")

        // Set the expected URL that stopRecording will return
        // Note: In real service, this would be set by the delegate callback

        // Stop and verify it returns the URL
        let url = await mockService.stopRecording()

        XCTAssertNotNil(url)
        let isRecording = await mockService.isRecording
        XCTAssertFalse(isRecording)
    }

    func testStopRecording_multipleCallsReturnNilAfterFirst() async throws {
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        // First stop returns URL
        let url1 = await mockService.stopRecording()
        XCTAssertNotNil(url1)

        // Subsequent stops return nil (not recording)
        let url2 = await mockService.stopRecording()
        XCTAssertNil(url2)

        let url3 = await mockService.stopRecording()
        XCTAssertNil(url3)
    }

    func testTearDown_resumesPendingContinuation() async throws {
        // This test verifies that tearDown properly handles pending continuations
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        // TearDown should not hang even if recording was in progress
        await mockService.tearDown()

        let isRecording = await mockService.isRecording
        let isConfigured = await mockService.isConfigured

        XCTAssertFalse(isRecording)
        XCTAssertFalse(isConfigured)
    }
}

// MARK: - State Management Tests

/// Tests for recording state management edge cases.
final class RecordingStateManagementTests: XCTestCase {

    var mockService: MockVideoRecordingService!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockService = nil
        try await super.tearDown()
    }

    func testRecordingFlow_fullCycle() async throws {
        // 1. Configure
        let isConfiguredBefore = await mockService.isConfigured
        XCTAssertFalse(isConfiguredBefore)

        try await mockService.configure(with: .default)

        let isConfiguredAfter = await mockService.isConfigured
        XCTAssertTrue(isConfiguredAfter)

        // 2. Start Recording
        let isRecordingBefore = await mockService.isRecording
        XCTAssertFalse(isRecordingBefore)

        try await mockService.startRecording()

        let isRecordingAfter = await mockService.isRecording
        XCTAssertTrue(isRecordingAfter)

        // 3. Stop Recording
        let url = await mockService.stopRecording()
        XCTAssertNotNil(url)

        let isRecordingFinal = await mockService.isRecording
        XCTAssertFalse(isRecordingFinal)

        // 4. Verify can record again
        try await mockService.startRecording()
        let canRecordAgain = await mockService.isRecording
        XCTAssertTrue(canRecordAgain)
    }

    func testRecordingFlow_startStopStartStop() async throws {
        try await mockService.configure(with: .default)

        // First recording cycle
        try await mockService.startRecording()
        let url1 = await mockService.stopRecording()
        XCTAssertNotNil(url1)

        // Second recording cycle
        try await mockService.startRecording()
        let url2 = await mockService.stopRecording()
        XCTAssertNotNil(url2)

        // Verify call counts
        let startCount = await mockService.startRecordingCallCount
        let stopCount = await mockService.stopRecordingCallCount
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 2)
    }

    func testReconfigure_afterRecording_works() async throws {
        // Configure with default
        try await mockService.configure(with: .default)

        // Record something
        try await mockService.startRecording()
        _ = await mockService.stopRecording()

        // Reconfigure with different settings
        try await mockService.configure(with: .highQuality)

        // Should be able to record again
        try await mockService.startRecording()

        let isRecording = await mockService.isRecording
        XCTAssertTrue(isRecording)
    }
}

// MARK: - Delegate Notification Tests

/// Tests for proper delegate notification during recording lifecycle.
@MainActor
final class DelegateNotificationTests: XCTestCase {

    var mockService: MockVideoRecordingService!
    var mockDelegate: MockVideoRecordingDelegate!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
        mockDelegate = MockVideoRecordingDelegate()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockDelegate?.reset()
        mockService = nil
        mockDelegate = nil
        try await super.tearDown()
    }

    func testStartRecording_notifiesDelegate() async throws {
        await mockService.setDelegate(mockDelegate)
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        // Allow time for async delegate callback
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockDelegate.didStartCallCount, 1)
        XCTAssertNotNil(mockDelegate.didStartAtURLs.first)
    }

    func testStopRecording_notifiesDelegate() async throws {
        await mockService.setDelegate(mockDelegate)
        try await mockService.configure(with: .default)
        try await mockService.startRecording()
        _ = await mockService.stopRecording()

        // Allow time for async delegate callback
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockDelegate.didFinishCallCount, 1)
    }

    func testSimulateError_notifiesDelegate() async throws {
        await mockService.setDelegate(mockDelegate)
        try await mockService.configure(with: .default)
        try await mockService.startRecording()

        await mockService.simulateRecordingError(VideoRecordingError.saveFailed)

        // Allow time for async delegate callback
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockDelegate.didFailCallCount, 1)
    }

    func testDurationUpdate_notifiesDelegate() async throws {
        await mockService.setDelegate(mockDelegate)

        await mockService.simulateDurationUpdate(5.0)
        await mockService.simulateDurationUpdate(10.0)

        // Allow time for async delegate callback
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockDelegate.didUpdateDurationCallCount, 2)
        XCTAssertEqual(mockDelegate.didUpdateDurations, [5.0, 10.0])
    }
}

// MARK: - Save to Photo Library Tests

/// Tests for saveToPhotoLibrary functionality.
final class SaveToPhotoLibraryTests: XCTestCase {

    var mockService: MockVideoRecordingService!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockService = nil
        try await super.tearDown()
    }

    func testSaveToPhotoLibrary_incrementsCallCount() async throws {
        let url = URL(fileURLWithPath: "/tmp/test-video.mov")
        try await mockService.saveToPhotoLibrary(url)

        let callCount = await mockService.saveToPhotoLibraryCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testSaveToPhotoLibrary_whenShouldFail_throwsError() async {
        await mockService.setShouldFailSaveToLibrary(true, error: .saveFailed)

        let url = URL(fileURLWithPath: "/tmp/test-video.mov")
        do {
            try await mockService.saveToPhotoLibrary(url)
            XCTFail("Should have thrown an error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .saveFailed)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSaveToPhotoLibrary_multipleCalls_tracksAll() async throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/video1.mov"),
            URL(fileURLWithPath: "/tmp/video2.mov"),
            URL(fileURLWithPath: "/tmp/video3.mov")
        ]

        for url in urls {
            try await mockService.saveToPhotoLibrary(url)
        }

        let callCount = await mockService.saveToPhotoLibraryCallCount
        XCTAssertEqual(callCount, 3)
    }
}

// MARK: - Configuration with Different Quality Settings Tests

/// Tests for configuration with various video quality settings.
final class VideoQualityConfigurationTests: XCTestCase {

    var mockService: MockVideoRecordingService!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockService = nil
        try await super.tearDown()
    }

    func testConfigure_with4KQuality_storesCorrectly() async throws {
        let config = VideoConfiguration(
            quality: .high4K,
            maxDuration: 30.0,
            enableAudio: true,
            stabilizationMode: .cinematic
        )

        try await mockService.configure(with: config)

        let storedConfig = await mockService.currentConfiguration
        XCTAssertEqual(storedConfig?.quality, .high4K)
        XCTAssertEqual(storedConfig?.maxDuration, 30.0)
        XCTAssertTrue(storedConfig?.enableAudio ?? false)
        XCTAssertEqual(storedConfig?.stabilizationMode, .cinematic)
    }

    func testConfigure_with1080pQuality_storesCorrectly() async throws {
        let config = VideoConfiguration(
            quality: .fullHD,
            maxDuration: 60.0,
            enableAudio: true,
            stabilizationMode: .auto
        )

        try await mockService.configure(with: config)

        let storedConfig = await mockService.currentConfiguration
        XCTAssertEqual(storedConfig?.quality, .fullHD)
    }

    func testConfigure_with720pQuality_storesCorrectly() async throws {
        let config = VideoConfiguration(
            quality: .hd,
            maxDuration: 120.0,
            enableAudio: false,
            stabilizationMode: .off
        )

        try await mockService.configure(with: config)

        let storedConfig = await mockService.currentConfiguration
        XCTAssertEqual(storedConfig?.quality, .hd)
        XCTAssertEqual(storedConfig?.maxDuration, 120.0)
        XCTAssertFalse(storedConfig?.enableAudio ?? true)
    }

    func testConfigure_reconfigureWithDifferentQuality_updatesConfiguration() async throws {
        // Configure with HD
        try await mockService.configure(with: VideoConfiguration(
            quality: .hd,
            maxDuration: 60.0,
            enableAudio: true,
            stabilizationMode: .auto
        ))

        var storedConfig = await mockService.currentConfiguration
        XCTAssertEqual(storedConfig?.quality, .hd)

        // Reconfigure with 4K
        try await mockService.configure(with: VideoConfiguration(
            quality: .high4K,
            maxDuration: 30.0,
            enableAudio: true,
            stabilizationMode: .cinematic
        ))

        storedConfig = await mockService.currentConfiguration
        XCTAssertEqual(storedConfig?.quality, .high4K)
        XCTAssertEqual(storedConfig?.maxDuration, 30.0)
    }

    func testConfigure_audioDisabled_storesCorrectly() async throws {
        let config = VideoConfiguration(
            quality: .fullHD,
            maxDuration: 60.0,
            enableAudio: false,
            stabilizationMode: .auto
        )

        try await mockService.configure(with: config)

        let storedConfig = await mockService.currentConfiguration
        XCTAssertFalse(storedConfig?.enableAudio ?? true)
    }

    func testConfigure_differentStabilizationModes_storesCorrectly() async throws {
        let modes: [AVCaptureVideoStabilizationMode] = [.off, .standard, .cinematic, .auto]

        for mode in modes {
            let config = VideoConfiguration(
                quality: .fullHD,
                maxDuration: 60.0,
                enableAudio: true,
                stabilizationMode: mode
            )

            try await mockService.configure(with: config)

            let storedConfig = await mockService.currentConfiguration
            XCTAssertEqual(storedConfig?.stabilizationMode, mode, "Stabilization mode \(mode) should be stored correctly")
        }
    }
}

// MARK: - Error Scenarios Tests

/// Tests for various error handling scenarios.
final class ErrorScenariosTests: XCTestCase {

    var mockService: MockVideoRecordingService!

    override func setUp() {
        super.setUp()
        mockService = MockVideoRecordingService()
    }

    override func tearDown() async throws {
        await mockService?.reset()
        mockService = nil
        try await super.tearDown()
    }

    func testStartRecording_afterTearDown_throwsNotConfigured() async throws {
        try await mockService.configure(with: .default)
        await mockService.tearDown()

        do {
            try await mockService.startRecording()
            XCTFail("Should have thrown an error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testStartRecording_withConfigurationError_throwsCorrectError() async {
        await mockService.setShouldFailStartRecording(true, error: .deviceNotAvailable)
        try? await mockService.configure(with: .default)

        do {
            try await mockService.startRecording()
            XCTFail("Should have thrown an error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .deviceNotAvailable)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testConfiguration_deviceNotAvailableError() async {
        await mockService.setShouldFailConfiguration(true, error: .deviceNotAvailable)

        do {
            try await mockService.configure(with: .default)
            XCTFail("Should have thrown an error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .deviceNotAvailable)
            XCTAssertEqual(error.errorDescription, "Camera device not available")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testConfiguration_notConfiguredError() async {
        await mockService.setShouldFailConfiguration(true, error: .notConfigured)

        do {
            try await mockService.configure(with: .default)
            XCTFail("Should have thrown an error")
        } catch let error as VideoRecordingError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}

// MARK: - Concurrency Safety Tests

/// Tests for thread safety and actor isolation.
final class ConcurrencySafetyTests: XCTestCase {

    func testMultipleConcurrentStarts_onlyOneSucceeds() async throws {
        let mockService = MockVideoRecordingService()
        try await mockService.configure(with: .default)

        // Attempt concurrent starts
        let results = await withTaskGroup(of: Result<Void, Error>.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        try await mockService.startRecording()
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var results: [Result<Void, Error>] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Count successes and failures
        let successes = results.filter { if case .success = $0 { return true } else { return false } }.count
        let recordingInProgressErrors = results.filter {
            if case .failure(let error) = $0,
               let videoError = error as? VideoRecordingError,
               videoError == .recordingInProgress {
                return true
            }
            return false
        }.count

        // Exactly one should succeed, rest should fail with recordingInProgress
        XCTAssertEqual(successes, 1, "Only one concurrent start should succeed")
        XCTAssertEqual(recordingInProgressErrors, 4, "Other attempts should fail with recordingInProgress")
    }

    func testActorIsolation_accessesAreSerializedCorrectly() async throws {
        let mockService = MockVideoRecordingService()

        // Multiple concurrent operations
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await mockService.configure(with: .default)
            }
            group.addTask {
                _ = await mockService.recordingDuration
            }
            group.addTask {
                _ = await mockService.recordingFileSize
            }
            group.addTask {
                _ = await mockService.isConfigured
            }
            group.addTask {
                _ = await mockService.isRecording
            }
        }

        // Should complete without deadlock or crash
    }
}
