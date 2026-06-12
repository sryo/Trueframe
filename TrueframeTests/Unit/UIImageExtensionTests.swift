// Unit tests for UIImage extensions.

import XCTest
@testable import Trueframe

/// Tests for UIImage+Rotation extension functionality.
final class UIImageExtensionTests: XCTestCase {

    // MARK: - averageBrightness Tests

    func testAverageBrightness_blackImage_returnsLowValue() {
        let blackImage = FakeCaptureEngine.makeImage(brightness: 0.0)

        let brightness = blackImage.averageBrightness()

        XCTAssertLessThan(brightness, 0.1, "Black image should have very low brightness")
    }

    func testAverageBrightness_whiteImage_returnsHighValue() {
        let whiteImage = FakeCaptureEngine.makeImage(brightness: 1.0)

        let brightness = whiteImage.averageBrightness()

        XCTAssertGreaterThan(brightness, 0.9, "White image should have very high brightness")
    }

    func testAverageBrightness_grayImage_returnsMidValue() {
        let grayImage = FakeCaptureEngine.makeImage(brightness: 0.5)

        let brightness = grayImage.averageBrightness()

        XCTAssertGreaterThan(brightness, 0.3)
        XCTAssertLessThan(brightness, 0.7)
    }

    func testAverageBrightness_invalidCGImage_returnsDefaultValue() {
        // An image that might not have a valid CGImage
        let renderer = UIGraphicsImageRenderer(size: .zero)
        let emptyImage = renderer.image { _ in }

        let brightness = emptyImage.averageBrightness()

        XCTAssertGreaterThanOrEqual(brightness, 0.0)
        XCTAssertLessThanOrEqual(brightness, 1.0)
    }

    // MARK: - isPitchBlack Tests

    func testIsPitchBlack_veryDarkImage_returnsTrue() {
        let darkImage = FakeCaptureEngine.makeImage(brightness: 0.02)

        XCTAssertTrue(darkImage.isPitchBlack, "Very dark image should be considered pitch black")
    }

    func testIsPitchBlack_blackImage_returnsTrue() {
        let blackImage = FakeCaptureEngine.makeImage(brightness: 0.0)

        XCTAssertTrue(blackImage.isPitchBlack)
    }

    func testIsPitchBlack_dimImage_returnsFalse() {
        // 10% brightness, above the 5% threshold
        let dimImage = FakeCaptureEngine.makeImage(brightness: 0.10)

        XCTAssertFalse(dimImage.isPitchBlack, "Dim but not pitch black image should return false")
    }

    func testIsPitchBlack_normalImage_returnsFalse() {
        let normalImage = FakeCaptureEngine.makeImage(brightness: 0.5)

        XCTAssertFalse(normalImage.isPitchBlack)
    }

    func testIsPitchBlack_whiteImage_returnsFalse() {
        let whiteImage = FakeCaptureEngine.makeImage(brightness: 1.0)

        XCTAssertFalse(whiteImage.isPitchBlack)
    }

    func testIsPitchBlack_borderlineImage_checkThreshold() {
        // Exactly at the 5% threshold: < 0.05 is pitch black, so this is not
        let borderlineImage = FakeCaptureEngine.makeImage(brightness: 0.05)

        XCTAssertFalse(borderlineImage.isPitchBlack, "Image at exactly 5% should not be pitch black")
    }

    func testIsPitchBlack_justBelowThreshold_returnsTrue() {
        let veryDarkImage = FakeCaptureEngine.makeImage(brightness: 0.04)

        XCTAssertTrue(veryDarkImage.isPitchBlack, "Image at 4% should be pitch black")
    }
}
