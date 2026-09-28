import XCTest
@testable import Trueframe

final class ScrubWheelMathTests: XCTestCase {

    func testGeometry_pitchIsItemWidthPlusSpacing() {
        XCTAssertEqual(ScrubWheelMath.windowWidth, 120)
        XCTAssertEqual(ScrubWheelMath.pitch, ScrubWheelMath.itemWidth + ScrubWheelMath.spacing)
    }

    func testNearestIndexForInterval_exactOption() {
        for (index, option) in CaptureSettings.intervalOptions.enumerated() {
            XCTAssertEqual(ScrubWheelMath.nearestIndex(for: option), index)
        }
    }

    func testNearestIndexForInterval_offGridValue_picksClosestOption() {
        XCTAssertEqual(ScrubWheelMath.nearestIndex(for: 2.4), 3)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(for: 60), 4)
    }

    func testNearestIndexForInterval_invalidValue_picksDefaultOption() {
        XCTAssertEqual(ScrubWheelMath.nearestIndex(for: .nan), 2)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(for: -1), 2)
    }

    func testRowOffset_centersTheIndexInTheWindow() {
        XCTAssertEqual(ScrubWheelMath.rowOffset(for: 0), 44)
        XCTAssertEqual(ScrubWheelMath.rowOffset(for: 2), 44 - 72)
        // The centered item's middle sits at the window's middle.
        let offset = ScrubWheelMath.rowOffset(for: 3)
        XCTAssertEqual(offset + 3 * 36 + 16, 60)
    }

    func testNearestIndex_roundsAndClamps() {
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: ScrubWheelMath.rowOffset(for: 2), count: 5), 2)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: ScrubWheelMath.rowOffset(for: 2) - 17, count: 5), 2)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: ScrubWheelMath.rowOffset(for: 2) - 19, count: 5), 3)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: 1_000, count: 5), 0)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: -1_000, count: 5), 4)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: 0, count: 0), 0)
    }

    func testNearestIndex_dragOfOnePitchMovesOneOption() {
        let offset = ScrubWheelMath.rowOffset(for: 2)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: offset - 36, count: 5), 3)
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: offset + 36, count: 5), 1)
    }

    func testNearestIndex_usesPitchNotItemWidth() {
        // Five item widths is five steps at 32pt but rounds to four at 36pt.
        let offset = ScrubWheelMath.rowOffset(for: 0) - 5 * 32
        XCTAssertEqual(ScrubWheelMath.nearestIndex(forRowOffset: offset, count: 6), 4)
    }

    func testTappedIndex_findsTheItemUnderTheFinger() {
        let offset = ScrubWheelMath.rowOffset(for: 2)
        XCTAssertEqual(ScrubWheelMath.tappedIndex(atX: 60, rowOffset: offset, count: 5), 2)
        XCTAssertEqual(ScrubWheelMath.tappedIndex(atX: 60 + 36, rowOffset: offset, count: 5), 3)
        XCTAssertEqual(ScrubWheelMath.tappedIndex(atX: 60 - 36, rowOffset: offset, count: 5), 1)
    }

    func testTappedIndex_clampsAtTheEnds() {
        let offset = ScrubWheelMath.rowOffset(for: 0)
        XCTAssertEqual(ScrubWheelMath.tappedIndex(atX: 2, rowOffset: offset, count: 5), 0)
        XCTAssertEqual(ScrubWheelMath.tappedIndex(atX: 118, rowOffset: ScrubWheelMath.rowOffset(for: 4), count: 5), 4)
    }

    func testDistance_isFractionalWhileDragging() {
        let offset = ScrubWheelMath.rowOffset(for: 2) - 18
        XCTAssertEqual(ScrubWheelMath.distance(of: 2, rowOffset: offset), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.distance(of: 3, rowOffset: offset), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.distance(of: 0, rowOffset: offset), 2.5, accuracy: 1e-9)
    }

    func testOpacity_fadesWithDistanceAndFloors() {
        XCTAssertEqual(ScrubWheelMath.opacity(atDistance: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.opacity(atDistance: 1), 0.65, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.opacity(atDistance: 2), 0.30, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.opacity(atDistance: 4), 0.15, accuracy: 1e-9)
    }

    func testScale_shrinksWithDistanceUpToTwoSteps() {
        XCTAssertEqual(ScrubWheelMath.scale(atDistance: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.scale(atDistance: 1), 0.92, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.scale(atDistance: 2), 0.84, accuracy: 1e-9)
        XCTAssertEqual(ScrubWheelMath.scale(atDistance: 3), 0.84, accuracy: 1e-9)
    }

    func testIsCentered_withinHalfAStep() {
        XCTAssertTrue(ScrubWheelMath.isCentered(atDistance: 0.49))
        XCTAssertFalse(ScrubWheelMath.isCentered(atDistance: 0.5))
    }

    func testSteppedIndex_clamps() {
        XCTAssertEqual(ScrubWheelMath.steppedIndex(from: 2, by: 1, count: 5), 3)
        XCTAssertEqual(ScrubWheelMath.steppedIndex(from: 4, by: 1, count: 5), 4)
        XCTAssertEqual(ScrubWheelMath.steppedIndex(from: 0, by: -1, count: 5), 0)
    }

    func testAccessibilityValue_readsAsSeconds() {
        XCTAssertEqual(ScrubWheelMath.accessibilityValue(for: 0.25), "0.25 seconds")
        XCTAssertEqual(ScrubWheelMath.accessibilityValue(for: 0.5), "0.5 seconds")
        XCTAssertEqual(ScrubWheelMath.accessibilityValue(for: 1), "1 second")
        XCTAssertEqual(ScrubWheelMath.accessibilityValue(for: 2), "2 seconds")
        XCTAssertEqual(ScrubWheelMath.accessibilityValue(for: 5), "5 seconds")
    }
}
