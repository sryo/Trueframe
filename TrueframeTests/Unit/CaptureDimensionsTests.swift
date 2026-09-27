// Choice of photo dimensions from what the camera format supports.

import CoreMedia
import XCTest
@testable import Trueframe

final class CaptureDimensionsTests: XCTestCase {

    private func dims(_ width: Int32, _ height: Int32) -> CMVideoDimensions {
        CMVideoDimensions(width: width, height: height)
    }

    private func assertEqual(_ a: CMVideoDimensions, _ b: CMVideoDimensions, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.width, b.width, file: file, line: line)
        XCTAssertEqual(a.height, b.height, file: file, line: line)
    }

    func testPicksLargestUnderCap() {
        let supported = [dims(4032, 3024), dims(8064, 6048), dims(5712, 4284), dims(1920, 1440)]
        let pick = CaptureEngine.targetDimensions(from: supported, maxPixelCount: 25_000_000)
        assertEqual(pick, dims(5712, 4284))
    }

    func testIncludesSizeExactlyAtCap() {
        let supported = [dims(1000, 1000), dims(2000, 1000)]
        let pick = CaptureEngine.targetDimensions(from: supported, maxPixelCount: 2_000_000)
        assertEqual(pick, dims(2000, 1000))
    }

    func testAllOverCap_picksSmallest() {
        let supported = [dims(8064, 6048), dims(5712, 4284), dims(6000, 5000)]
        let pick = CaptureEngine.targetDimensions(from: supported, maxPixelCount: 1_000_000)
        assertEqual(pick, dims(5712, 4284))
    }

    func testEmpty_fallsBackTo12MP() {
        let pick = CaptureEngine.targetDimensions(from: [], maxPixelCount: 25_000_000)
        assertEqual(pick, dims(4032, 3024))
    }
}
