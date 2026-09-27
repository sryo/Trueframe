// Unit tests for the interval picker's index math.

import XCTest
@testable import Trueframe

final class IntervalPickerGeometryTests: XCTestCase {

    func testPitch_isItemWidthPlusSpacing() {
        XCTAssertEqual(IntervalPickerGeometry.itemWidth, 32)
        XCTAssertEqual(IntervalPickerGeometry.spacing, 4)
        XCTAssertEqual(IntervalPickerGeometry.pitch, 36)
    }

    // MARK: - nearestIndex

    func testNearestIndex_exactOption() {
        for (index, option) in CaptureSettings.intervalOptions.enumerated() {
            XCTAssertEqual(IntervalPickerGeometry.nearestIndex(for: option), index)
        }
    }

    func testNearestIndex_offGridValue_picksClosestOption() {
        XCTAssertEqual(IntervalPickerGeometry.nearestIndex(for: 2.4), 3)
        XCTAssertEqual(IntervalPickerGeometry.nearestIndex(for: 60), 4)
    }

    func testNearestIndex_invalidValue_picksDefaultOption() {
        XCTAssertEqual(IntervalPickerGeometry.nearestIndex(for: .nan), 2)
        XCTAssertEqual(IntervalPickerGeometry.nearestIndex(for: -1), 2)
    }

    // MARK: - previewIndex

    private func preview(current: Int, drag: CGFloat, count: Int = 5) -> Int {
        IntervalPickerGeometry.previewIndex(current: current, dragOffset: drag, pitch: 36, count: count)
    }

    func testPreviewIndex_noDrag_staysOnCurrent() {
        XCTAssertEqual(preview(current: 2, drag: 0), 2)
    }

    func testPreviewIndex_dragLeftOnePitch_movesToNextOption() {
        XCTAssertEqual(preview(current: 2, drag: -36), 3)
    }

    func testPreviewIndex_dragRightOnePitch_movesToPreviousOption() {
        XCTAssertEqual(preview(current: 2, drag: 36), 1)
    }

    func testPreviewIndex_roundsAtHalfPitch() {
        XCTAssertEqual(preview(current: 2, drag: -17), 2)
        XCTAssertEqual(preview(current: 2, drag: -19), 3)
    }

    func testPreviewIndex_usesPitchNotItemWidth() {
        // Five item widths is five steps at 32pt but rounds to four at 36pt.
        XCTAssertEqual(preview(current: 0, drag: -5 * 32, count: 6), 4)
    }

    func testPreviewIndex_clampsToBounds() {
        XCTAssertEqual(preview(current: 2, drag: -1_000), 4)
        XCTAssertEqual(preview(current: 2, drag: 1_000), 0)
    }

    func testPreviewIndex_degenerateInput_isSafe() {
        XCTAssertEqual(preview(current: 0, drag: -36, count: 0), 0)
        XCTAssertEqual(IntervalPickerGeometry.previewIndex(current: 1, dragOffset: 50, pitch: 0, count: 5), 1)
    }
}
