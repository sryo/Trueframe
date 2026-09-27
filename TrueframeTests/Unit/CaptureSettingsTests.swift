// Unit tests for CaptureSettings.

import XCTest
@testable import Trueframe

@MainActor
final class CaptureSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: CaptureSettings!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        sut = CaptureSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testDefault_captureIntervalIsOneSecond() {
        XCTAssertEqual(sut.captureInterval, 1.0)
    }

    func testIntervalOptions_areSortedAndIncludeDefault() {
        XCTAssertEqual(CaptureSettings.intervalOptions, [0.25, 0.5, 1.0, 2.0, 5.0])
        XCTAssertTrue(CaptureSettings.intervalOptions.contains(sut.captureInterval))
    }

    // MARK: - Persistence

    func testPersistence_everyOptionRoundTrips() {
        for interval in CaptureSettings.intervalOptions {
            sut.captureInterval = interval

            XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, interval)
        }
    }

    func testPersistence_writesUnderIntervalKey() {
        sut.captureInterval = 2.0

        XCTAssertEqual(defaults.double(forKey: "capture.interval"), 2.0)
    }

    func testInit_readsStoredOption() {
        defaults.set(5.0, forKey: "capture.interval")

        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 5.0)
    }

    func testPersistence_doesNotTouchStandardDefaults() {
        let before = UserDefaults.standard.object(forKey: "capture.interval") as? Double

        sut.captureInterval = 5.0

        XCTAssertEqual(UserDefaults.standard.object(forKey: "capture.interval") as? Double, before)
    }

    // MARK: - Formatting

    func testFormatInterval_options() {
        let formats = CaptureSettings.intervalOptions.map(CaptureSettings.formatInterval)
        XCTAssertEqual(formats, ["0.25s", "0.5s", "1s", "2s", "5s"])
    }

    func testFormatInterval_wholeSecondsHaveNoDecimal() {
        XCTAssertEqual(CaptureSettings.formatInterval(3.0), "3s")
        XCTAssertEqual(CaptureSettings.formatInterval(10.0), "10s")
    }
}
