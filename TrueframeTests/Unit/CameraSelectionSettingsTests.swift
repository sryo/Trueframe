// Unit tests for CameraSelectionSettings.

import XCTest
@testable import Trueframe

/// Tests for CameraSelectionSettings functionality.
final class CameraSelectionSettingsTests: XCTestCase {

    var sut: CameraSelectionSettings!

    override func setUp() {
        super.setUp()
        // Clear UserDefaults for clean test state
        clearUserDefaults()
        sut = CameraSelectionSettings()
    }

    override func tearDown() {
        sut = nil
        clearUserDefaults()
        super.tearDown()
    }

    private func clearUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "camera.selected")
        defaults.removeObject(forKey: "camera.flash")
    }

    // MARK: - Default Values Tests

    func testDefaultValues_wideSelected() {
        XCTAssertEqual(sut.selectedCamera, .wide, "Wide should be selected by default")
        XCTAssertTrue(sut.wideEnabled, "Wide should be enabled by default")
    }

    func testDefaultValues_ultrawideNotSelected() {
        XCTAssertFalse(sut.ultrawideEnabled, "Ultrawide should not be enabled by default")
    }

    func testDefaultValues_telephotoNotSelected() {
        XCTAssertFalse(sut.telephotoEnabled, "Telephoto should not be enabled by default")
    }

    func testDefaultValues_flashDisabled() {
        XCTAssertFalse(sut.flashEnabled, "Flash should be disabled by default")
    }

    // MARK: - Mutually Exclusive Selection Tests

    func testSelect_switchesToNewCamera() {
        sut.select(.ultrawide)

        XCTAssertEqual(sut.selectedCamera, .ultrawide)
        XCTAssertTrue(sut.ultrawideEnabled)
        XCTAssertFalse(sut.wideEnabled)
        XCTAssertFalse(sut.telephotoEnabled)
    }

    func testSelect_disablesPreviousCamera() {
        sut.select(.wide)
        XCTAssertTrue(sut.wideEnabled)

        sut.select(.telephoto)

        XCTAssertFalse(sut.wideEnabled, "Wide should be disabled after selecting telephoto")
        XCTAssertTrue(sut.telephotoEnabled)
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

    // MARK: - isEnabled Tests

    func testIsEnabled_wide() {
        sut.select(.wide)
        XCTAssertTrue(sut.isEnabled(.wide))
        XCTAssertFalse(sut.isEnabled(.ultrawide))
        XCTAssertFalse(sut.isEnabled(.telephoto))
    }

    func testIsEnabled_ultrawide() {
        sut.select(.ultrawide)
        XCTAssertTrue(sut.isEnabled(.ultrawide))
        XCTAssertFalse(sut.isEnabled(.wide))
        XCTAssertFalse(sut.isEnabled(.telephoto))
    }

    func testIsEnabled_telephoto() {
        sut.select(.telephoto)
        XCTAssertTrue(sut.isEnabled(.telephoto))
        XCTAssertFalse(sut.isEnabled(.wide))
        XCTAssertFalse(sut.isEnabled(.ultrawide))
    }

    // MARK: - BackCameraType Tests

    func testBackCameraType_allCases() {
        let allCases = BackCameraType.allCases

        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.wide))
        XCTAssertTrue(allCases.contains(.ultrawide))
        XCTAssertTrue(allCases.contains(.telephoto))
    }

    func testBackCameraType_isEquatable() {
        XCTAssertEqual(BackCameraType.wide, BackCameraType.wide)
        XCTAssertNotEqual(BackCameraType.wide, BackCameraType.ultrawide)
    }

    func testBackCameraType_rawValue() {
        XCTAssertEqual(BackCameraType.wide.rawValue, "wide")
        XCTAssertEqual(BackCameraType.ultrawide.rawValue, "ultrawide")
        XCTAssertEqual(BackCameraType.telephoto.rawValue, "telephoto")
    }

    func testBackCameraType_initFromRawValue() {
        XCTAssertEqual(BackCameraType(rawValue: "wide"), .wide)
        XCTAssertEqual(BackCameraType(rawValue: "ultrawide"), .ultrawide)
        XCTAssertEqual(BackCameraType(rawValue: "telephoto"), .telephoto)
        XCTAssertNil(BackCameraType(rawValue: "invalid"))
    }
}
