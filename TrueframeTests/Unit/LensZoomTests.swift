// Unit tests for the lens selector's zoom label and selection styling.

import XCTest
@testable import Trueframe

final class LensZoomTests: XCTestCase {

    private func teleFOV(zoom: Double, wideFOV: Double) -> Double {
        let halfWide = wideFOV * .pi / 360
        return atan(tan(halfWide) / zoom) * 360 / .pi
    }

    // MARK: - Zoom label

    func testZoomLabel_twoTimes() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 2, wideFOV: 77), wideFOV: 77), "2x")
    }

    func testZoomLabel_threeTimes() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 3, wideFOV: 73), wideFOV: 73), "3x")
    }

    func testZoomLabel_fiveTimes() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 5, wideFOV: 78), wideFOV: 78), "5x")
    }

    func testZoomLabel_roundsToNearestWholeFactor() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 2.9, wideFOV: 77), wideFOV: 77), "3x")
    }

    func testZoomLabel_clampsBelowTwo() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 1.2, wideFOV: 77), wideFOV: 77), "2x")
    }

    func testZoomLabel_clampsAboveTen() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 25, wideFOV: 77), wideFOV: 77), "10x")
    }

    func testZoomLabel_withoutWide_assumesTypicalWideFOV() {
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 3, wideFOV: 77), wideFOV: nil), "3x")
    }

    func testZoomLabel_withoutTele_fallsBackToTwo() {
        XCTAssertEqual(zoomLabel(teleFOV: nil, wideFOV: 77), "2x")
    }

    func testZoomLabel_ignoresNonPositiveFOV() {
        XCTAssertEqual(zoomLabel(teleFOV: 0, wideFOV: 77), "2x")
        XCTAssertEqual(zoomLabel(teleFOV: teleFOV(zoom: 3, wideFOV: 77), wideFOV: 0), "3x")
    }

    // MARK: - Selection styling

    func testLensStyle_selectedIsFullSize() {
        XCTAssertEqual(LensStyle.scale(isSelected: true), 1.0)
        XCTAssertEqual(LensStyle.labelOpacity(isSelected: true), 0.9)
    }

    func testLensStyle_unselectedShrinksAndDims() {
        XCTAssertEqual(LensStyle.scale(isSelected: false), 0.86)
        XCTAssertEqual(LensStyle.labelOpacity(isSelected: false), 0.3)
    }
}
