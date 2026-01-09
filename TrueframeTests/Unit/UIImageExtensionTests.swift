// Unit tests for UIImage extensions.

import XCTest
@testable import Trueframe

/// Tests for UIImage+Rotation extension functionality.
final class UIImageExtensionTests: XCTestCase {

    // MARK: - correctedForOrientation Tests

    func testCorrectedForOrientation_upOrientation_returnsSameImage() {
        // Given
        let image = createTestImage(orientation: .up)

        // When
        let corrected = image.correctedForOrientation()

        // Then
        XCTAssertEqual(corrected.size, image.size)
        XCTAssertEqual(corrected.imageOrientation, .up)
    }

    func testCorrectedForOrientation_leftOrientation_correctsOrientation() {
        // Given
        let image = createTestImage(orientation: .left)

        // When
        let corrected = image.correctedForOrientation()

        // Then
        XCTAssertEqual(corrected.imageOrientation, .up)
    }

    func testCorrectedForOrientation_rightOrientation_correctsOrientation() {
        // Given
        let image = createTestImage(orientation: .right)

        // When
        let corrected = image.correctedForOrientation()

        // Then
        XCTAssertEqual(corrected.imageOrientation, .up)
    }

    func testCorrectedForOrientation_downOrientation_correctsOrientation() {
        // Given
        let image = createTestImage(orientation: .down)

        // When
        let corrected = image.correctedForOrientation()

        // Then
        XCTAssertEqual(corrected.imageOrientation, .up)
    }

    // MARK: - averageBrightness Tests

    func testAverageBrightness_blackImage_returnsLowValue() {
        // Given
        let blackImage = createSolidColorImage(color: .black)

        // When
        let brightness = blackImage.averageBrightness()

        // Then
        XCTAssertLessThan(brightness, 0.1, "Black image should have very low brightness")
    }

    func testAverageBrightness_whiteImage_returnsHighValue() {
        // Given
        let whiteImage = createSolidColorImage(color: .white)

        // When
        let brightness = whiteImage.averageBrightness()

        // Then
        XCTAssertGreaterThan(brightness, 0.9, "White image should have very high brightness")
    }

    func testAverageBrightness_grayImage_returnsMidValue() {
        // Given
        let grayImage = createSolidColorImage(color: .gray)

        // When
        let brightness = grayImage.averageBrightness()

        // Then
        XCTAssertGreaterThan(brightness, 0.3)
        XCTAssertLessThan(brightness, 0.7)
    }

    func testAverageBrightness_invalidCGImage_returnsDefaultValue() {
        // Given - create an image that might not have a valid CGImage
        let renderer = UIGraphicsImageRenderer(size: .zero)
        let emptyImage = renderer.image { _ in }

        // When
        let brightness = emptyImage.averageBrightness()

        // Then - should return default value without crashing
        XCTAssertGreaterThanOrEqual(brightness, 0.0)
        XCTAssertLessThanOrEqual(brightness, 1.0)
    }

    // MARK: - isPitchBlack Tests

    func testIsPitchBlack_veryDarkImage_returnsTrue() {
        // Given - image with less than 5% brightness
        let darkImage = createSolidColorImage(brightness: 0.02)

        // When
        let isPitchBlack = darkImage.isPitchBlack

        // Then
        XCTAssertTrue(isPitchBlack, "Very dark image should be considered pitch black")
    }

    func testIsPitchBlack_blackImage_returnsTrue() {
        // Given
        let blackImage = createSolidColorImage(color: .black)

        // When
        let isPitchBlack = blackImage.isPitchBlack

        // Then
        XCTAssertTrue(isPitchBlack)
    }

    func testIsPitchBlack_dimImage_returnsFalse() {
        // Given - image with 10% brightness (above 5% threshold)
        let dimImage = createSolidColorImage(brightness: 0.10)

        // When
        let isPitchBlack = dimImage.isPitchBlack

        // Then
        XCTAssertFalse(isPitchBlack, "Dim but not pitch black image should return false")
    }

    func testIsPitchBlack_normalImage_returnsFalse() {
        // Given
        let normalImage = createSolidColorImage(color: .gray)

        // When
        let isPitchBlack = normalImage.isPitchBlack

        // Then
        XCTAssertFalse(isPitchBlack)
    }

    func testIsPitchBlack_whiteImage_returnsFalse() {
        // Given
        let whiteImage = createSolidColorImage(color: .white)

        // When
        let isPitchBlack = whiteImage.isPitchBlack

        // Then
        XCTAssertFalse(isPitchBlack)
    }

    func testIsPitchBlack_borderlineImage_checkThreshold() {
        // Given - exactly at 5% threshold
        let borderlineImage = createSolidColorImage(brightness: 0.05)

        // When
        let isPitchBlack = borderlineImage.isPitchBlack

        // Then - at exactly 5%, should be false (< 0.05 is pitch black)
        XCTAssertFalse(isPitchBlack, "Image at exactly 5% should not be pitch black")
    }

    func testIsPitchBlack_justBelowThreshold_returnsTrue() {
        // Given - just below 5% threshold
        let veryDarkImage = createSolidColorImage(brightness: 0.04)

        // When
        let isPitchBlack = veryDarkImage.isPitchBlack

        // Then
        XCTAssertTrue(isPitchBlack, "Image at 4% should be pitch black")
    }

    // MARK: - Helpers

    private func createTestImage(orientation: UIImage.Orientation) -> UIImage {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let baseImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        guard let cgImage = baseImage.cgImage else {
            return baseImage
        }

        return UIImage(cgImage: cgImage, scale: baseImage.scale, orientation: orientation)
    }

    private func createSolidColorImage(color: UIColor, size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func createSolidColorImage(brightness: CGFloat, size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        let color = UIColor(white: brightness, alpha: 1.0)
        return createSolidColorImage(color: color, size: size)
    }
}
