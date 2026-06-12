// Unit tests for CaptureSettings.

import XCTest
@testable import Trueframe

/// Tests for CaptureSettings functionality.
@MainActor
final class CaptureSettingsTests: XCTestCase {

    var sut: CaptureSettings!

    override func setUp() async throws {
        try await super.setUp()
        TestDefaults.clear()
        sut = CaptureSettings()
    }

    override func tearDown() async throws {
        sut = nil
        TestDefaults.clear()
        try await super.tearDown()
    }

    // MARK: - Default Values Tests

    func testDefaultValues_captureIntervalIsOneSecond() {
        XCTAssertEqual(sut.captureInterval, 1.0, "Default capture interval should be 1.0 second")
    }

    // MARK: - Capture Interval Options Tests

    func testIntervalOptions_containsExpectedValues() {
        let expectedOptions: [Double] = [0.25, 0.5, 1.0, 2.0, 5.0]
        XCTAssertEqual(CaptureSettings.intervalOptions, expectedOptions)
    }

    func testIntervalOptions_hasFiveOptions() {
        XCTAssertEqual(CaptureSettings.intervalOptions.count, 5)
    }

    func testIntervalOptions_firstIsBurstLike() {
        XCTAssertEqual(CaptureSettings.intervalOptions.first, 0.25, "First option should be 0.25s (burst-like)")
    }

    func testIntervalOptions_lastIsFiveSeconds() {
        XCTAssertEqual(CaptureSettings.intervalOptions.last, 5.0, "Last option should be 5.0s")
    }

    func testIntervalOptions_areSortedAscending() {
        let sorted = CaptureSettings.intervalOptions.sorted()
        XCTAssertEqual(CaptureSettings.intervalOptions, sorted, "Interval options should be sorted in ascending order")
    }

    func testIntervalOptions_defaultValueIsInOptions() {
        XCTAssertTrue(
            CaptureSettings.intervalOptions.contains(sut.captureInterval),
            "Default capture interval should be one of the available options"
        )
    }

    // MARK: - Setting Capture Interval Tests

    func testCaptureInterval_canSetToEachOption() {
        for interval in CaptureSettings.intervalOptions {
            sut.captureInterval = interval
            XCTAssertEqual(sut.captureInterval, interval)
        }
    }

    // MARK: - Format Interval Tests

    func testFormatInterval_allOptionsFormatCorrectly() {
        let expectedFormats = ["0.25s", "0.5s", "1s", "2s", "5s"]
        let actualFormats = CaptureSettings.intervalOptions.map { CaptureSettings.formatInterval($0) }
        XCTAssertEqual(actualFormats, expectedFormats)
    }

    func testFormatInterval_subSecondUsesDecimal() {
        XCTAssertTrue(CaptureSettings.formatInterval(0.1).contains("."))
        XCTAssertTrue(CaptureSettings.formatInterval(0.75).contains("."))
    }

    func testFormatInterval_wholeSecondsUseInteger() {
        XCTAssertFalse(CaptureSettings.formatInterval(1.0).contains("."))
        XCTAssertFalse(CaptureSettings.formatInterval(3.0).contains("."))
        XCTAssertFalse(CaptureSettings.formatInterval(10.0).contains("."))
    }

    // MARK: - Persistence Tests

    func testPersistence_captureInterval_allOptions() {
        for interval in CaptureSettings.intervalOptions {
            TestDefaults.clear()
            sut = CaptureSettings()
            sut.captureInterval = interval

            let newInstance = CaptureSettings()

            XCTAssertEqual(newInstance.captureInterval, interval, "captureInterval=\(interval) should persist")
        }
    }

    func testUserDefaults_usesCorrectKeyForCaptureInterval() {
        sut.captureInterval = 2.5

        let storedValue = UserDefaults.standard.double(forKey: "capture.interval")
        XCTAssertEqual(storedValue, 2.5)
    }

    func testInit_readsExistingCaptureIntervalValue() {
        UserDefaults.standard.set(3.5, forKey: "capture.interval")

        let instance = CaptureSettings()

        XCTAssertEqual(instance.captureInterval, 3.5)
    }

    // MARK: - Edge Cases Tests

    func testCaptureInterval_acceptsArbitraryValue() {
        // The model accepts any Double, not just predefined options
        sut.captureInterval = 3.0
        XCTAssertEqual(sut.captureInterval, 3.0)

        let newInstance = CaptureSettings()
        XCTAssertEqual(newInstance.captureInterval, 3.0)
    }

    func testMultipleInstances_shareSettings() {
        let instance1 = CaptureSettings()
        instance1.captureInterval = 2.0

        let instance2 = CaptureSettings()

        XCTAssertEqual(instance2.captureInterval, 2.0, "New instances should read persisted values")
    }
}
