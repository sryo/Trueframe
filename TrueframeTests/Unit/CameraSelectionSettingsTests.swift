// Unit tests for CameraSelectionSettings.

import XCTest
@testable import Trueframe

/// Tests for CameraSelectionSettings functionality.
@MainActor
final class CameraSelectionSettingsTests: XCTestCase {

    var sut: CameraSelectionSettings!

    override func setUp() async throws {
        try await super.setUp()
        TestDefaults.clear()
        sut = CameraSelectionSettings()
    }

    override func tearDown() async throws {
        sut = nil
        TestDefaults.clear()
        try await super.tearDown()
    }

    // MARK: - Default Values Tests

    func testDefaultValues_wideSelected() {
        XCTAssertEqual(sut.selectedCamera, .wide, "Wide should be selected by default")
    }

    func testDefaultValues_flashDisabled() {
        XCTAssertFalse(sut.flashEnabled, "Flash should be disabled by default")
    }

    // MARK: - Mutually Exclusive Selection Tests

    func testSelect_switchesToNewCamera() {
        sut.select(.ultrawide)

        XCTAssertEqual(sut.selectedCamera, .ultrawide)
    }

    func testSelect_replacesPreviousSelection() {
        sut.select(.wide)
        sut.select(.telephoto)

        XCTAssertEqual(sut.selectedCamera, .telephoto, "Selection is mutually exclusive")
    }

    // MARK: - Persistence Tests

    func testPersistence_selectedCamera() {
        sut.select(.telephoto)

        // Create new instance to verify persistence
        let newInstance = CameraSelectionSettings()

        XCTAssertEqual(newInstance.selectedCamera, .telephoto, "Selected camera should persist")
    }

    func testPersistence_flashEnabled() {
        sut.flashEnabled = true

        let newInstance = CameraSelectionSettings()

        XCTAssertTrue(newInstance.flashEnabled, "Flash setting should persist")
    }

    // MARK: - BackCameraType Tests

    func testBackCameraType_allCases() {
        let allCases = BackCameraType.allCases

        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.wide))
        XCTAssertTrue(allCases.contains(.ultrawide))
        XCTAssertTrue(allCases.contains(.telephoto))
    }

    func testBackCameraType_rawValueRoundTrip() {
        for camera in BackCameraType.allCases {
            XCTAssertEqual(BackCameraType(rawValue: camera.rawValue), camera)
        }
        XCTAssertNil(BackCameraType(rawValue: "invalid"))
    }
}
