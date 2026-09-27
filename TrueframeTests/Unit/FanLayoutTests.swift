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

    func testPhotos_showsTheFirstSeven() {
        let images = (0..<10).map { _ in UIImage() }
        let shown = FanLayout.photos(from: images)
        XCTAssertEqual(shown.count, 7)
        XCTAssertTrue(shown[0] === images[0])
        XCTAssertTrue(shown[6] === images[6])
    }
}
