import XCTest
import SwiftUI
@testable import Trueframe

final class FanLayoutTests: XCTestCase {

    func testSlots_emptySessionHasNoSlots() {
        XCTAssertTrue(FanLayout.slots(count: 0).isEmpty)
    }

    func testSlots_neverMoreThanSeven() {
        XCTAssertEqual(FanLayout.maxPhotos, 7)
        XCTAssertEqual(FanLayout.slots(count: 12).count, 7)
    }

    func testSlots_spreadEvenlyFromMinusToPlusTwentyFiveDegrees() {
        let degrees = FanLayout.slots(count: 7).map(\.rotation.degrees)
        let expected = (0..<7).map { -25.0 + Double($0) * 50.0 / 6 }
        XCTAssertEqual(degrees.count, expected.count)
        for (actual, want) in zip(degrees, expected) {
            XCTAssertEqual(actual, want, accuracy: 1e-9)
        }
    }

    func testSlots_sitOnAnArcAroundAPivotBelowCenter() {
        for slot in FanLayout.slots(count: 7) {
            let fromPivot = CGSize(width: slot.offset.width, height: slot.offset.height - FanLayout.pivotDrop)
            XCTAssertEqual(hypot(fromPivot.width, fromPivot.height), FanLayout.radius, accuracy: 1e-9)
        }
        let middle = FanLayout.slots(count: 7)[3]
        XCTAssertEqual(middle.offset.width, 0, accuracy: 1e-9)
        XCTAssertEqual(middle.offset.height, 200 - 240, accuracy: 1e-9)
    }

    func testSlots_mirrorAcrossTheMiddle() {
        let slots = FanLayout.slots(count: 4)
        XCTAssertEqual(slots[0].offset.width, -slots[3].offset.width, accuracy: 1e-9)
        XCTAssertEqual(slots[0].offset.height, slots[3].offset.height, accuracy: 1e-9)
        XCTAssertEqual(slots[1].rotation.degrees, -slots[2].rotation.degrees, accuracy: 1e-9)
    }

    func testSlots_singlePhotoStandsUprightAtTheTop() {
        let slots = FanLayout.slots(count: 1)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].rotation.degrees, 0)
        XCTAssertEqual(slots[0].offset.width, 0, accuracy: 1e-9)
        XCTAssertEqual(slots[0].offset.height, -40, accuracy: 1e-9)
    }

    func testDelay_staggersThirtyMillisecondsPerPhoto() {
        XCTAssertEqual(FanLayout.delay(for: 0), 0)
        XCTAssertEqual(FanLayout.delay(for: 4), 0.12, accuracy: 1e-9)
    }

    func testShown_smallSessionShowsEveryPhoto() {
        XCTAssertEqual(FanLayout.shownIndices(count: 5, kept: [false, true, false, true, false]), [0, 1, 2, 3, 4])
    }

    func testShown_withoutAVerdictShowsTheFirstSeven() {
        XCTAssertEqual(FanLayout.shownIndices(count: 10, kept: nil), Array(0..<7))
    }

    func testShown_prefersKeptPhotosThenFillsWithDropsInCaptureOrder() {
        let kept = [false, true, false, true, false, false, false, false, true, false]
        XCTAssertEqual(FanLayout.shownIndices(count: 10, kept: kept), [0, 1, 2, 3, 4, 5, 8])
    }

    func testShown_manyKeepersLeaveNoRoomForDrops() {
        let kept = (0..<12).map { $0 % 4 != 0 }
        XCTAssertEqual(FanLayout.shownIndices(count: 12, kept: kept), [1, 2, 3, 5, 6, 7, 9])
    }

    func testKeptFlags_withoutAVerdictKeepEverything() {
        XCTAssertEqual(FanLayout.keptFlags(shown: [0, 2, 3], verdict: nil), [true, true, true])
    }

    func testKeptFlags_followTheVerdictForTheShownPhotos() {
        XCTAssertEqual(FanLayout.keptFlags(shown: [0, 2, 3], verdict: [true, true, false, true]), [true, false, true])
    }

    func testKeptFlags_neverDropEveryShownPhoto() {
        XCTAssertEqual(FanLayout.keptFlags(shown: [1, 2], verdict: [true, false, false]), [true, true],
                       "Something has to reach the heart")
    }

    func testVerdictDeadline_isShort() {
        XCTAssertLessThanOrEqual(FanLayout.verdictDeadline, .seconds(0.5))
        XCTAssertLessThanOrEqual(FanLayout.fanVerdictGrace, .seconds(0.25))
    }

    @MainActor
    func testAwaitVerdict_returnsAsSoonAsItIsKnown() async {
        let start = ContinuousClock.now
        let verdict = await FanLayout.awaitVerdict(within: .seconds(2)) { [true, false] }
        XCTAssertEqual(verdict, [true, false])
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(100))
    }

    @MainActor
    func testAwaitVerdict_givesUpAtTheDeadline() async {
        let start = ContinuousClock.now
        let verdict = await FanLayout.awaitVerdict(within: .milliseconds(60)) { nil }
        XCTAssertNil(verdict)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(60))
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(500))
    }
}
