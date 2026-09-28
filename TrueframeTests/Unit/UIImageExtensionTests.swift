import XCTest
@testable import Trueframe

final class UIImageExtensionTests: XCTestCase {

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
        let renderer = UIGraphicsImageRenderer(size: .zero)
        let emptyImage = renderer.image { _ in }

        let brightness = emptyImage.averageBrightness()

        XCTAssertEqual(brightness, 0.5)
    }

    func testIsPitchBlack_veryDarkImage_returnsTrue() {
        let darkImage = FakeCaptureEngine.makeImage(brightness: 0.02)

        XCTAssertTrue(darkImage.isPitchBlack, "Very dark image should be considered pitch black")
    }

    func testIsPitchBlack_blackImage_returnsTrue() {
        let blackImage = FakeCaptureEngine.makeImage(brightness: 0.0)

        XCTAssertTrue(blackImage.isPitchBlack)
    }

    func testIsPitchBlack_dimImage_returnsFalse() {
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
}
