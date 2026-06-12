// Unit tests for the lunar phase arithmetic.

import XCTest
@testable import Trueframe

final class DateMoonTests: XCTestCase {

    /// 2000-01-06 18:14 UTC, the reference new moon.
    private let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)
    private let synodicMonth = 29.53059 * 86_400

    func testReferenceNewMoon_hasAgeZero() {
        XCTAssertEqual(referenceNewMoon.lunarAgeDays, 0, accuracy: 0.001)
    }

    func testReferenceNewMoon_isNotFull() {
        XCTAssertFalse(referenceNewMoon.isNearFullMoon)
    }

    func testHalfCycleAfterNewMoon_isFull() {
        let fullMoon = referenceNewMoon.addingTimeInterval(synodicMonth / 2)
        XCTAssertTrue(fullMoon.isNearFullMoon)
    }

    func testQuarterCycle_isNotFull() {
        let quarter = referenceNewMoon.addingTimeInterval(synodicMonth / 4)
        XCTAssertFalse(quarter.isNearFullMoon)
    }

    func testPhase_isPeriodic() {
        // 300 cycles later, half-cycle is still full and zero is still new
        // (age may wrap to ~29.53 instead of 0 from float accumulation)
        let manyCyclesLater = referenceNewMoon.addingTimeInterval(synodicMonth * 300)
        let age = manyCyclesLater.lunarAgeDays
        let distanceFromNew = min(age, 29.53059 - age)
        XCTAssertEqual(distanceFromNew, 0, accuracy: 0.001)
        XCTAssertTrue(manyCyclesLater.addingTimeInterval(synodicMonth / 2).isNearFullMoon)
    }

    func testDatesBeforeReference_haveValidAge() {
        let earlier = referenceNewMoon.addingTimeInterval(-synodicMonth / 2)
        XCTAssertEqual(earlier.lunarAgeDays, 29.53059 / 2, accuracy: 0.001)
        XCTAssertTrue(earlier.isNearFullMoon)
    }

    func testAge_staysInRange() {
        for offset in stride(from: -5.0, through: 5.0, by: 0.7) {
            let date = referenceNewMoon.addingTimeInterval(synodicMonth * offset * 1.37)
            XCTAssertGreaterThanOrEqual(date.lunarAgeDays, 0)
            XCTAssertLessThan(date.lunarAgeDays, 29.53059)
        }
    }
}
