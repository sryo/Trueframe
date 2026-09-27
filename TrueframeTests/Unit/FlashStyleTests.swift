// Unit tests for the flash button's hit area and spoken state.

import XCTest
@testable import Trueframe

final class FlashStyleTests: XCTestCase {

    func testHitInset_growsTwentyFourPointGlyphToFortyFour() {
        XCTAssertEqual(FlashStyle.hitInset(visualSize: 24), -10)
    }

    func testHitInset_neverShrinksLargerButtons() {
        XCTAssertEqual(FlashStyle.hitInset(visualSize: 52), 0)
    }

    func testAccessibilityValue_readsOnAndOff() {
        XCTAssertEqual(FlashStyle.accessibilityValue(isOn: true), "On")
        XCTAssertEqual(FlashStyle.accessibilityValue(isOn: false), "Off")
    }

    func testSymbol_swapsBetweenBoltAndSlashedBolt() {
        XCTAssertEqual(FlashStyle.symbol(isOn: true), "bolt.fill")
        XCTAssertEqual(FlashStyle.symbol(isOn: false), "bolt.slash")
    }
}
