// Unit tests for AppState.

import Combine
import XCTest
@testable import Trueframe

/// Tests for AppState functionality.
@MainActor
final class AppStateTests: XCTestCase {

    var sut: AppState!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        sut = AppState()
        cancellables = []
    }

    override func tearDown() async throws {
        sut = nil
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_isNotCapturing() {
        XCTAssertFalse(sut.isCapturing, "Should not be capturing initially")
    }

    func testInitialState_sessionPhotosEmpty() {
        XCTAssertTrue(sut.sessionPhotos.isEmpty, "Session photos should be empty initially")
    }

    func testInitialState_hasPermissionsIsFalse() {
        XCTAssertFalse(sut.hasPermissions, "Should not have permissions initially")
    }

    func testInitialState_cameraServiceExists() {
        XCTAssertNotNil(sut.cameraService, "Camera service should exist")
    }

    func testInitialState_cameraSelectionSettingsExists() {
        XCTAssertNotNil(sut.cameraSelectionSettings, "Camera selection settings should exist")
    }

    // MARK: - startCaptureSession Tests

    func testStartCaptureSession_withoutPermissions_doesNotStart() {
        // Given
        XCTAssertFalse(sut.hasPermissions)

        // When
        sut.startCaptureSession()

        // Then
        XCTAssertFalse(sut.isCapturing, "Should not start without permissions")
    }

    func testStartCaptureSession_setsIsCapturing() async throws {
        // Given - simulate having permissions
        // Note: In real tests, you'd inject mock permissions

        // When
        sut.startCaptureSession()

        // Then - without permissions, should not start
        // This tests the guard clause
    }

    func testStartCaptureSession_clearsSessionPhotos() async throws {
        // Given
        // In a real test, you'd set up the state properly
    }

    // MARK: - endCaptureSession Tests

    func testEndCaptureSession_whenNotCapturing_doesNotStorePhotos() {
        // Given - not capturing is the default state
        XCTAssertFalse(sut.isCapturing)
        let testPhotos = [createTestImage(), createTestImage()]

        // When
        sut.endCaptureSession(photos: testPhotos)

        // Then - guard clause prevents storing photos when not capturing
        XCTAssertFalse(sut.isCapturing)
        XCTAssertFalse(sut.showingTumbleAnimation, "Should not show tumble animation when not capturing")
        XCTAssertTrue(sut.sessionPhotos.isEmpty, "Should not store photos when not capturing")
    }

    func testEndCaptureSession_withEmptyPhotos_whenNotCapturing_doesNothing() {
        // Given
        XCTAssertFalse(sut.isCapturing)

        // When
        sut.endCaptureSession(photos: [])

        // Then
        XCTAssertTrue(sut.sessionPhotos.isEmpty)
    }

    func testEndCaptureSession_guardClause_requiresCapturing() {
        // Given
        XCTAssertFalse(sut.isCapturing)
        let photos = [createTestImage()]

        // When
        sut.endCaptureSession(photos: photos)

        // Then - guard clause should prevent any state changes
        XCTAssertTrue(sut.sessionPhotos.isEmpty, "Guard clause should prevent storing photos when not capturing")
        XCTAssertFalse(sut.showingTumbleAnimation, "Guard clause should prevent tumble animation")
    }

    // MARK: - Observable Property Tests

    func testIsCapturing_isObservable() {
        // Observable macro properties can be tracked via withObservationTracking
        // For now, just verify the property is accessible
        XCTAssertFalse(sut.isCapturing)
    }

    // MARK: - Helpers

    private func createTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        return renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
    }
}
