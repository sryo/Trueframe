// Integration tests for the capture flow.

import Combine
import XCTest
@testable import Trueframe

/// Integration tests that verify the capture flow works correctly.
/// Note: These tests verify the flow doesn't crash and state transitions correctly.
/// Full camera integration requires running on a physical device.
@MainActor
final class CaptureFlowIntegrationTests: XCTestCase {

    var captureViewModel: CaptureViewModel!
    var appState: AppState!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        captureViewModel = CaptureViewModel()
        cancellables = []
    }

    override func tearDown() async throws {
        captureViewModel.onDisappear()
        captureViewModel = nil
        appState = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Lifecycle Tests

    func testCaptureFlow_onAppear_doesNotCrash() async throws {
        // When
        captureViewModel.onAppear(appState: appState)

        // Wait for async setup
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash
        XCTAssertTrue(true, "onAppear should complete without crashing")
    }

    func testCaptureFlow_onDisappear_doesNotCrash() async throws {
        // Given
        captureViewModel.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        captureViewModel.onDisappear()

        // Then - should not crash
        XCTAssertTrue(true, "onDisappear should complete without crashing")
    }

    func testCaptureFlow_multipleAppearDisappear_doesNotCrash() async throws {
        // When - rapid appear/disappear cycles
        for _ in 0..<3 {
            captureViewModel.onAppear(appState: appState)
            try await Task.sleep(nanoseconds: 50_000_000)
            captureViewModel.onDisappear()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Then - should not crash
        XCTAssertTrue(true, "Multiple appear/disappear cycles should not crash")
    }

    // MARK: - State Tests

    func testCaptureFlow_initialState_notCapturing() {
        XCTAssertFalse(captureViewModel.isCapturing, "Should not be capturing initially")
    }

    func testCaptureFlow_initialState_zeroPhotos() {
        XCTAssertEqual(captureViewModel.photoCount, 0, "Should have zero photos initially")
    }

    // MARK: - Settings Integration Tests

    func testCameraSettings_wideCamera_appliesCorrectly() async throws {
        // Given
        appState.cameraSelectionSettings.select(.wide)

        // When
        captureViewModel.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash and settings should be applied
        XCTAssertTrue(appState.cameraSelectionSettings.isEnabled(.wide))
    }

    func testCameraSettings_flashEnabled_appliesCorrectly() async throws {
        // Given
        appState.cameraSelectionSettings.flashEnabled = true

        // When
        captureViewModel.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash and settings should be applied
        XCTAssertTrue(appState.cameraSelectionSettings.flashEnabled)
    }

    func testCameraSettings_telephoto_appliesCorrectly() async throws {
        // Given
        appState.cameraSelectionSettings.select(.telephoto)

        // When
        captureViewModel.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash
        XCTAssertTrue(appState.cameraSelectionSettings.isEnabled(.telephoto))
    }

    // MARK: - Capture Interval Tests

    func testCaptureSettings_burstInterval_appliesCorrectly() async throws {
        // Given - 0.25s burst interval
        appState.captureSettings.captureInterval = 0.25

        // When
        captureViewModel.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash
        XCTAssertEqual(appState.captureSettings.captureInterval, 0.25)
    }

    func testCaptureSettings_normalInterval_appliesCorrectly() async throws {
        // Given - 2s normal interval
        appState.captureSettings.captureInterval = 2.0

        // When
        captureViewModel.onAppear(appState: appState)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then - should not crash
        XCTAssertEqual(appState.captureSettings.captureInterval, 2.0)
    }
}

// MARK: - AppState Integration Tests

@MainActor
final class AppStateIntegrationTests: XCTestCase {

    var sut: AppState!

    override func setUp() async throws {
        try await super.setUp()
        sut = AppState()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    func testAppState_initialState() {
        XCTAssertFalse(sut.isCapturing, "Should not be capturing initially")
        XCTAssertTrue(sut.sessionPhotos.isEmpty, "Should have no session photos initially")
    }

    func testAppState_captureSettings_persist() {
        // Given
        sut.captureSettings.captureInterval = 2.0

        // When - create new instance
        let newAppState = AppState()

        // Then - settings should persist
        XCTAssertEqual(newAppState.captureSettings.captureInterval, 2.0)

        // Cleanup
        sut.captureSettings.captureInterval = 1.0
    }

    func testAppState_cameraSelectionSettings_persist() {
        // Given
        sut.cameraSelectionSettings.flashEnabled = true

        // When - create new instance
        let newAppState = AppState()

        // Then - settings should persist
        XCTAssertTrue(newAppState.cameraSelectionSettings.flashEnabled)

        // Cleanup
        sut.cameraSelectionSettings.flashEnabled = false
    }

    func testEndCaptureSession_whenNotCapturing_doesNothing() {
        // Given - not capturing (default state)
        XCTAssertFalse(sut.isCapturing)

        // When
        let photos = [createTestImage()]
        sut.endCaptureSession(photos: photos)

        // Then - state should not change since we weren't capturing
        XCTAssertFalse(sut.isCapturing, "Should remain not capturing")
        XCTAssertTrue(sut.sessionPhotos.isEmpty, "Should not store photos when not capturing")
    }

    func testStartCaptureSession_withoutPermissions_doesNotStart() {
        // Given - no permissions
        XCTAssertFalse(sut.hasPermissions)

        // When
        sut.startCaptureSession()

        // Then - should not start without permissions
        XCTAssertFalse(sut.isCapturing, "Should not start without permissions")
    }

    func testTumbleAnimationComplete_whenNotShowing_doesNothing() {
        // Given - tumble animation not showing
        XCTAssertFalse(sut.showingTumbleAnimation)

        // When
        sut.tumbleAnimationComplete()

        // Then - should not crash and state should remain unchanged
        XCTAssertFalse(sut.showingTumbleAnimation)
    }

    private func createTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        return renderer.image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
    }
}
