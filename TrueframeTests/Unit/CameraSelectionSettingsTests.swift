// Unit tests for CameraSelectionSettings.

import XCTest
@testable import Trueframe

@MainActor
final class CameraSelectionSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: CameraSelectionSettings!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        sut = CameraSelectionSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testDefault_wideSelected() {
        XCTAssertEqual(sut.selectedCamera, .wide)
    }

    func testDefault_flashDisabled() {
        XCTAssertFalse(sut.flashEnabled)
    }

    // MARK: - Selection

    func testSelect_replacesPreviousSelection() {
        sut.select(.ultrawide)
        sut.select(.telephoto)

        XCTAssertEqual(sut.selectedCamera, .telephoto)
    }

    // MARK: - Persistence

    func testPersistence_selectedCamera() {
        sut.select(.telephoto)

        XCTAssertEqual(CameraSelectionSettings(defaults: defaults).selectedCamera, .telephoto)
    }

    func testPersistence_flashEnabled() {
        sut.flashEnabled = true

        XCTAssertTrue(CameraSelectionSettings(defaults: defaults).flashEnabled)
    }

    func testInit_unknownStoredCamera_fallsBackToWide() {
        defaults.set("fisheye", forKey: "camera.selected")

        XCTAssertEqual(CameraSelectionSettings(defaults: defaults).selectedCamera, .wide)
    }

    // MARK: - BackCameraType

    func testBackCameraType_rawValueRoundTrip() {
        XCTAssertEqual(BackCameraType.allCases, [.wide, .ultrawide, .telephoto])
        for camera in BackCameraType.allCases {
            XCTAssertEqual(BackCameraType(rawValue: camera.rawValue), camera)
        }
        XCTAssertNil(BackCameraType(rawValue: "invalid"))
    }
}
