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

    func testDefault_captureIntervalIsOneSecond() {
        XCTAssertEqual(sut.captureInterval, 1.0)
    }

    func testIntervalOptions_areSortedAndIncludeDefault() {
        XCTAssertEqual(CaptureSettings.intervalOptions, [0.25, 0.5, 1.0, 2.0, 5.0])
        XCTAssertTrue(CaptureSettings.intervalOptions.contains(sut.captureInterval))
    }

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

    func testInit_storedOffGridValue_snapsToNearestOption() {
        defaults.set(2.4, forKey: "capture.interval")

        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 2.0)
    }

    func testInit_storedValueBeyondRange_snapsToEnd() {
        defaults.set(60.0, forKey: "capture.interval")

        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 5.0)
    }

    func testInit_storedNonPositive_fallsBackToOneSecond() {
        defaults.set(-3.0, forKey: "capture.interval")
        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 1.0)

        defaults.set(0.0, forKey: "capture.interval")
        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 1.0)
    }

    func testInit_storedNonFinite_fallsBackToOneSecond() {
        defaults.set(Double.nan, forKey: "capture.interval")
        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 1.0)

        defaults.set(Double.infinity, forKey: "capture.interval")
        XCTAssertEqual(CaptureSettings(defaults: defaults).captureInterval, 1.0)
    }

    func testSet_offGridValue_snapsAndPersistsTheOption() {
        sut.captureInterval = 0.3

        XCTAssertEqual(sut.captureInterval, 0.25)
        XCTAssertEqual(defaults.double(forKey: "capture.interval"), 0.25)
    }

    func testSet_nonFinite_fallsBackToOneSecond() {
        sut.captureInterval = 5.0
        sut.captureInterval = .nan

        XCTAssertEqual(sut.captureInterval, 1.0)
    }

    func testFormatInterval_options() {
        let formats = CaptureSettings.intervalOptions.map(CaptureSettings.formatInterval)
        XCTAssertEqual(formats, ["0.25s", "0.5s", "1s", "2s", "5s"])
    }

    func testFormatInterval_wholeSecondsHaveNoDecimal() {
        XCTAssertEqual(CaptureSettings.formatInterval(3.0), "3s")
        XCTAssertEqual(CaptureSettings.formatInterval(10.0), "10s")
    }

    func testFormatInterval_keepsFractionAboveOneSecond() {
        XCTAssertEqual(CaptureSettings.formatInterval(1.5), "1.5s")
        XCTAssertEqual(CaptureSettings.formatInterval(2.25), "2.25s")
    }
}
