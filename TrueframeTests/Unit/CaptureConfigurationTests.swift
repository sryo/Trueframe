// Unit tests for CaptureConfiguration's flash rule.

import XCTest
@testable import Trueframe

final class CaptureConfigurationTests: XCTestCase {

    private func configuration(flash: Bool, interval: Double) -> CaptureConfiguration {
        CaptureConfiguration(lens: .wide, flashEnabled: flash, interval: interval)
    }

    func testResolvedFlash_atMinimumInterval_isEnabled() {
        let sut = configuration(flash: true, interval: CaptureConfiguration.minimumFlashInterval)

        XCTAssertTrue(sut.resolvedFlashEnabled)
    }

    func testResolvedFlash_aboveMinimumInterval_isEnabled() {
        XCTAssertTrue(configuration(flash: true, interval: 5.0).resolvedFlashEnabled)
    }

    func testResolvedFlash_belowMinimumInterval_isDisabled() {
        XCTAssertFalse(configuration(flash: true, interval: 0.5).resolvedFlashEnabled)
    }

    func testResolvedFlash_userDisabled_staysDisabled() {
        XCTAssertFalse(configuration(flash: false, interval: 5.0).resolvedFlashEnabled)
    }
}
