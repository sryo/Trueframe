// Stillness bookkeeping behind the motion monitor.

import XCTest
@testable import Trueframe

final class StillnessReadingTests: XCTestCase {

    func testNotStillBeforeAnySample() {
        var reading = StillnessReading()
        _ = reading.begin()
        XCTAssertFalse(reading.isStill)
    }

    func testSampleBelowThreshold_isStill() {
        var reading = StillnessReading()
        let run = reading.begin()
        reading.record(MotionMonitor.stillnessThreshold / 2, run: run)
        XCTAssertTrue(reading.isStill)
    }

    func testSampleAboveThreshold_isNotStill() {
        var reading = StillnessReading()
        let run = reading.begin()
        reading.record(MotionMonitor.stillnessThreshold * 2, run: run)
        XCTAssertFalse(reading.isStill)
    }

    func testEnd_forgetsLastSample() {
        var reading = StillnessReading()
        let run = reading.begin()
        reading.record(0, run: run)
        reading.end()
        XCTAssertFalse(reading.isStill)
    }

    func testSampleArrivingAfterEnd_isIgnored() {
        var reading = StillnessReading()
        let run = reading.begin()
        reading.end()
        reading.record(0, run: run)
        XCTAssertFalse(reading.isStill)
    }

    func testSampleFromEarlierRun_isIgnoredByNextRun() {
        var reading = StillnessReading()
        let first = reading.begin()
        reading.end()
        _ = reading.begin()
        reading.record(0, run: first)
        XCTAssertFalse(reading.isStill)
    }
}
