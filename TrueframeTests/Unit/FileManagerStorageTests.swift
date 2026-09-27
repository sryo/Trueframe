import XCTest
@testable import Trueframe

final class FileManagerStorageTests: XCTestCase {

    private let minimum = FileManager.minimumRequiredSpace

    func testUnknownCapacity_failsOpen() {
        XCTAssertTrue(FileManager.hasAdequateSpace(available: nil))
    }

    func testPlentyOfSpace_isAdequate() {
        XCTAssertTrue(FileManager.hasAdequateSpace(available: minimum * 10))
    }

    func testAtOrBelowMinimum_isNotAdequate() {
        XCTAssertFalse(FileManager.hasAdequateSpace(available: minimum))
        XCTAssertFalse(FileManager.hasAdequateSpace(available: 0))
    }

    func testJustAboveMinimum_isAdequate() {
        XCTAssertTrue(FileManager.hasAdequateSpace(available: minimum + 1))
    }
}
