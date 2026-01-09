// Unit tests for CaptureSettings.

import XCTest
@testable import Trueframe

/// Tests for CaptureSettings functionality.
final class CaptureSettingsTests: XCTestCase {

    var sut: CaptureSettings!

    override func setUp() {
        super.setUp()
        // Clear UserDefaults for clean test state
        clearUserDefaults()
        sut = CaptureSettings()
    }

    override func tearDown() {
        sut = nil
        clearUserDefaults()
        super.tearDown()
    }

    private func clearUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "capture.livePhotos")
        defaults.removeObject(forKey: "capture.smartSelection")
        defaults.removeObject(forKey: "capture.autoSaveBest")
        defaults.removeObject(forKey: "capture.interval")
    }

    // MARK: - Default Values Tests

    func testDefaultValues_livePhotosEnabled() {
        XCTAssertTrue(sut.livePhotosEnabled, "Live photos should be enabled by default")
    }

    func testDefaultValues_smartSelectionEnabled() {
        XCTAssertTrue(sut.smartSelectionEnabled, "Smart selection should be enabled by default")
    }

    func testDefaultValues_autoSaveBestEnabled() {
        XCTAssertTrue(sut.autoSaveBest, "Auto save best should be enabled by default")
    }

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

    func testCaptureInterval_canSetToQuarterSecond() {
        sut.captureInterval = 0.25
        XCTAssertEqual(sut.captureInterval, 0.25)
    }

    func testCaptureInterval_canSetToHalfSecond() {
        sut.captureInterval = 0.5
        XCTAssertEqual(sut.captureInterval, 0.5)
    }

    func testCaptureInterval_canSetToOneSecond() {
        sut.captureInterval = 1.0
        XCTAssertEqual(sut.captureInterval, 1.0)
    }

    func testCaptureInterval_canSetToTwoSeconds() {
        sut.captureInterval = 2.0
        XCTAssertEqual(sut.captureInterval, 2.0)
    }

    func testCaptureInterval_canSetToFiveSeconds() {
        sut.captureInterval = 5.0
        XCTAssertEqual(sut.captureInterval, 5.0)
    }

    // MARK: - Format Interval Tests

    func testFormatInterval_quarterSecond() {
        let formatted = CaptureSettings.formatInterval(0.25)
        XCTAssertEqual(formatted, "0.25s", "Quarter second should format as '0.25s'")
    }

    func testFormatInterval_halfSecond() {
        let formatted = CaptureSettings.formatInterval(0.5)
        XCTAssertEqual(formatted, "0.5s", "Half second should format as '0.5s'")
    }

    func testFormatInterval_oneSecond() {
        let formatted = CaptureSettings.formatInterval(1.0)
        XCTAssertEqual(formatted, "1s", "One second should format as '1s'")
    }

    func testFormatInterval_twoSeconds() {
        let formatted = CaptureSettings.formatInterval(2.0)
        XCTAssertEqual(formatted, "2s", "Two seconds should format as '2s'")
    }

    func testFormatInterval_fiveSeconds() {
        let formatted = CaptureSettings.formatInterval(5.0)
        XCTAssertEqual(formatted, "5s", "Five seconds should format as '5s'")
    }

    func testFormatInterval_allOptionsFormatCorrectly() {
        let expectedFormats = ["0.25s", "0.5s", "1s", "2s", "5s"]
        let actualFormats = CaptureSettings.intervalOptions.map { CaptureSettings.formatInterval($0) }
        XCTAssertEqual(actualFormats, expectedFormats)
    }

    func testFormatInterval_subSecondUsesDecimal() {
        // Test various sub-second values
        XCTAssertTrue(CaptureSettings.formatInterval(0.1).contains("."))
        XCTAssertTrue(CaptureSettings.formatInterval(0.75).contains("."))
    }

    func testFormatInterval_wholeSecondsUseInteger() {
        // Test whole second values don't contain decimal
        XCTAssertFalse(CaptureSettings.formatInterval(1.0).contains("."))
        XCTAssertFalse(CaptureSettings.formatInterval(3.0).contains("."))
        XCTAssertFalse(CaptureSettings.formatInterval(10.0).contains("."))
    }

    // MARK: - Persistence Tests - livePhotosEnabled

    func testPersistence_livePhotosEnabled_true() {
        sut.livePhotosEnabled = true

        let newInstance = CaptureSettings()

        XCTAssertTrue(newInstance.livePhotosEnabled, "livePhotosEnabled=true should persist")
    }

    func testPersistence_livePhotosEnabled_false() {
        sut.livePhotosEnabled = false

        let newInstance = CaptureSettings()

        XCTAssertFalse(newInstance.livePhotosEnabled, "livePhotosEnabled=false should persist")
    }

    // MARK: - Persistence Tests - smartSelectionEnabled

    func testPersistence_smartSelectionEnabled_true() {
        sut.smartSelectionEnabled = true

        let newInstance = CaptureSettings()

        XCTAssertTrue(newInstance.smartSelectionEnabled, "smartSelectionEnabled=true should persist")
    }

    func testPersistence_smartSelectionEnabled_false() {
        sut.smartSelectionEnabled = false

        let newInstance = CaptureSettings()

        XCTAssertFalse(newInstance.smartSelectionEnabled, "smartSelectionEnabled=false should persist")
    }

    // MARK: - Persistence Tests - autoSaveBest

    func testPersistence_autoSaveBest_true() {
        sut.autoSaveBest = true

        let newInstance = CaptureSettings()

        XCTAssertTrue(newInstance.autoSaveBest, "autoSaveBest=true should persist")
    }

    func testPersistence_autoSaveBest_false() {
        sut.autoSaveBest = false

        let newInstance = CaptureSettings()

        XCTAssertFalse(newInstance.autoSaveBest, "autoSaveBest=false should persist")
    }

    // MARK: - Persistence Tests - captureInterval

    func testPersistence_captureInterval_quarterSecond() {
        sut.captureInterval = 0.25

        let newInstance = CaptureSettings()

        XCTAssertEqual(newInstance.captureInterval, 0.25, "captureInterval=0.25 should persist")
    }

    func testPersistence_captureInterval_halfSecond() {
        sut.captureInterval = 0.5

        let newInstance = CaptureSettings()

        XCTAssertEqual(newInstance.captureInterval, 0.5, "captureInterval=0.5 should persist")
    }

    func testPersistence_captureInterval_oneSecond() {
        sut.captureInterval = 1.0

        let newInstance = CaptureSettings()

        XCTAssertEqual(newInstance.captureInterval, 1.0, "captureInterval=1.0 should persist")
    }

    func testPersistence_captureInterval_twoSeconds() {
        sut.captureInterval = 2.0

        let newInstance = CaptureSettings()

        XCTAssertEqual(newInstance.captureInterval, 2.0, "captureInterval=2.0 should persist")
    }

    func testPersistence_captureInterval_fiveSeconds() {
        sut.captureInterval = 5.0

        let newInstance = CaptureSettings()

        XCTAssertEqual(newInstance.captureInterval, 5.0, "captureInterval=5.0 should persist")
    }

    func testPersistence_captureInterval_allOptions() {
        for interval in CaptureSettings.intervalOptions {
            clearUserDefaults()
            sut = CaptureSettings()
            sut.captureInterval = interval

            let newInstance = CaptureSettings()

            XCTAssertEqual(newInstance.captureInterval, interval, "captureInterval=\(interval) should persist")
        }
    }

    // MARK: - Multiple Settings Persistence Tests

    func testPersistence_multipleSettingsAtOnce() {
        sut.livePhotosEnabled = false
        sut.smartSelectionEnabled = false
        sut.autoSaveBest = false
        sut.captureInterval = 2.0

        let newInstance = CaptureSettings()

        XCTAssertFalse(newInstance.livePhotosEnabled)
        XCTAssertFalse(newInstance.smartSelectionEnabled)
        XCTAssertFalse(newInstance.autoSaveBest)
        XCTAssertEqual(newInstance.captureInterval, 2.0)
    }

    func testPersistence_settingsAreIndependent() {
        // Change only captureInterval
        sut.captureInterval = 5.0

        let newInstance = CaptureSettings()

        // Other settings should remain at defaults
        XCTAssertTrue(newInstance.livePhotosEnabled, "Unchanged settings should remain at default")
        XCTAssertTrue(newInstance.smartSelectionEnabled, "Unchanged settings should remain at default")
        XCTAssertTrue(newInstance.autoSaveBest, "Unchanged settings should remain at default")
        // Changed setting should persist
        XCTAssertEqual(newInstance.captureInterval, 5.0)
    }

    // MARK: - Edge Cases Tests

    func testCaptureInterval_acceptsArbitraryValue() {
        // The model accepts any Double, not just predefined options
        sut.captureInterval = 3.0
        XCTAssertEqual(sut.captureInterval, 3.0)

        let newInstance = CaptureSettings()
        XCTAssertEqual(newInstance.captureInterval, 3.0)
    }

    func testCaptureInterval_acceptsZero() {
        sut.captureInterval = 0.0
        XCTAssertEqual(sut.captureInterval, 0.0)
    }

    func testCaptureInterval_acceptsVerySmallValue() {
        sut.captureInterval = 0.01
        XCTAssertEqual(sut.captureInterval, 0.01)
    }

    func testCaptureInterval_acceptsLargeValue() {
        sut.captureInterval = 60.0
        XCTAssertEqual(sut.captureInterval, 60.0)
    }

    // MARK: - UserDefaults Key Tests

    func testUserDefaults_usesCorrectKeyForLivePhotos() {
        sut.livePhotosEnabled = false

        let storedValue = UserDefaults.standard.bool(forKey: "capture.livePhotos")
        XCTAssertFalse(storedValue)
    }

    func testUserDefaults_usesCorrectKeyForSmartSelection() {
        sut.smartSelectionEnabled = false

        let storedValue = UserDefaults.standard.bool(forKey: "capture.smartSelection")
        XCTAssertFalse(storedValue)
    }

    func testUserDefaults_usesCorrectKeyForAutoSaveBest() {
        sut.autoSaveBest = false

        let storedValue = UserDefaults.standard.bool(forKey: "capture.autoSaveBest")
        XCTAssertFalse(storedValue)
    }

    func testUserDefaults_usesCorrectKeyForCaptureInterval() {
        sut.captureInterval = 2.5

        let storedValue = UserDefaults.standard.double(forKey: "capture.interval")
        XCTAssertEqual(storedValue, 2.5)
    }

    // MARK: - Initialization from Existing UserDefaults Tests

    func testInit_readsExistingLivePhotosValue() {
        UserDefaults.standard.set(false, forKey: "capture.livePhotos")

        let instance = CaptureSettings()

        XCTAssertFalse(instance.livePhotosEnabled)
    }

    func testInit_readsExistingSmartSelectionValue() {
        UserDefaults.standard.set(false, forKey: "capture.smartSelection")

        let instance = CaptureSettings()

        XCTAssertFalse(instance.smartSelectionEnabled)
    }

    func testInit_readsExistingAutoSaveBestValue() {
        UserDefaults.standard.set(false, forKey: "capture.autoSaveBest")

        let instance = CaptureSettings()

        XCTAssertFalse(instance.autoSaveBest)
    }

    func testInit_readsExistingCaptureIntervalValue() {
        UserDefaults.standard.set(3.5, forKey: "capture.interval")

        let instance = CaptureSettings()

        XCTAssertEqual(instance.captureInterval, 3.5)
    }

    // MARK: - Multiple Instances Tests

    func testMultipleInstances_shareSettings() {
        let instance1 = CaptureSettings()
        _ = CaptureSettings()

        instance1.captureInterval = 2.0

        // instance2 won't see the change until it's re-initialized
        // because it reads from UserDefaults on init
        let instance3 = CaptureSettings()

        XCTAssertEqual(instance3.captureInterval, 2.0, "New instances should read persisted values")
    }

    // MARK: - Type Safety Tests

    func testStaticProperties_areCorrectTypes() {
        // Verify intervalOptions is [Double]
        let intervals: [Double] = CaptureSettings.intervalOptions
        XCTAssertNotNil(intervals)
    }

    func testFormatInterval_returnsString() {
        let result: String = CaptureSettings.formatInterval(1.0)
        XCTAssertNotNil(result)
        XCTAssertFalse(result.isEmpty)
    }
}
