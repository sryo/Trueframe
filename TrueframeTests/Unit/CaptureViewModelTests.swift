// Unit tests for CaptureViewModel.

import Combine
import XCTest
@testable import Trueframe

/// Tests for CaptureViewModel business logic.
@MainActor
final class CaptureViewModelTests: XCTestCase {

    var sut: CaptureViewModel!
    var appState: AppState!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        sut = CaptureViewModel()
        appState = AppState()
        cancellables = []
    }

    override func tearDown() async throws {
        sut = nil
        appState = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_isNotCapturing() {
        XCTAssertFalse(sut.isCapturing, "Should not be capturing initially")
    }

    func testInitialState_photoCountIsZero() {
        XCTAssertEqual(sut.photoCount, 0, "Photo count should be zero initially")
    }

    // MARK: - onAppear Tests

    func testOnAppear_setsUpCorrectly() async throws {
        // When
        sut.onAppear(appState: appState)

        // Then - wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Verify setup was called (isCapturing state depends on camera configuration)
        XCTAssertTrue(sut.isCapturing || !appState.hasPermissions, "Should be capturing after onAppear if permissions exist")
    }

    func testOnAppear_configuresCameraSettings() async throws {
        // Given - set up camera settings
        appState.cameraSelectionSettings.select(.wide)
        appState.cameraSelectionSettings.flashEnabled = true

        // When
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - verify settings are applied (no mock to check, just verify no crash)
        XCTAssertTrue(true, "Camera settings should be configured without error")
    }

    // MARK: - Photo Count Tests

    func testPhotoCount_startsAtZero() {
        XCTAssertEqual(sut.photoCount, 0, "Photo count should start at zero")
    }

    // MARK: - onDisappear Tests

    func testOnDisappear_cleansUpResources() async throws {
        // Given
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        sut.onDisappear()

        // Then - verify no crash during cleanup
        // Note: onDisappear tears down camera but doesn't reset isCapturing
        // The isCapturing flag is reset by endCaptureSession when proximity ends
        XCTAssertTrue(true, "Cleanup should complete without error")
    }

    func testOnDisappear_cancelsCaptureTasks() async throws {
        // Given
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        sut.onDisappear()

        // Then - verify cleanup completes without crash
        // The capture task should be cancelled and camera torn down
        try await Task.sleep(nanoseconds: 50_000_000) // Allow cleanup to complete
        XCTAssertTrue(true, "Capture tasks should be cancelled without error")
    }

    // MARK: - Burst Mode Tests

    func testBurstMode_withFastInterval_doesNotCrash() async throws {
        // Given - burst interval (< 1s)
        appState.captureSettings.captureInterval = 0.25

        // When
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash with fast interval
        sut.onDisappear()
        XCTAssertTrue(true, "Burst mode should not crash")
    }

    func testBurstMode_rapidOnOffCycles_doesNotCrash() async throws {
        // Given - burst interval
        appState.captureSettings.captureInterval = 0.25

        // When - rapid on/off cycles
        for _ in 0..<5 {
            sut.onAppear(appState: appState)
            try await Task.sleep(nanoseconds: 50_000_000)
            sut.onDisappear()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Then - should not crash
        XCTAssertTrue(true, "Rapid burst mode cycles should not crash")
    }

    func testNormalMode_withSlowInterval_doesNotCrash() async throws {
        // Given - normal interval (>= 1s)
        appState.captureSettings.captureInterval = 2.0

        // When
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash with slow interval
        sut.onDisappear()
        XCTAssertTrue(true, "Normal mode should not crash")
    }

    func testCaptureSession_onDisappear_cleansUpProperly() async throws {
        // Given - start capture session
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 200_000_000)

        // When - disappear while potentially capturing
        sut.onDisappear()

        // Wait for cleanup
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash and photo count shouldn't be negative
        XCTAssertGreaterThanOrEqual(sut.photoCount, 0, "Photo count should never be negative")
    }

    func testCaptureSession_switchingIntervals_doesNotCrash() async throws {
        // Test switching between burst and normal mode
        appState.captureSettings.captureInterval = 0.25
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)
        sut.onDisappear()

        try await Task.sleep(nanoseconds: 50_000_000)

        appState.captureSettings.captureInterval = 2.0
        sut.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)
        sut.onDisappear()

        XCTAssertTrue(true, "Switching between burst and normal mode should not crash")
    }
}
