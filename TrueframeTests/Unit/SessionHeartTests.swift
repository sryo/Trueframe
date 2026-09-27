import XCTest
@testable import Trueframe

final class SessionHeartTests: XCTestCase {

    func testAfterglow_restsFaintlyWhileCapturing() {
        XCTAssertEqual(SessionHeart.afterglowResting, 0.12)
    }

    func testAfterglow_pulsesUpQuicklyAndFadesBackSlowly() {
        let steps = SessionHeart.afterglowPulse
        XCTAssertEqual(steps.map(\.opacity), [0.4, 0.12])
        XCTAssertEqual(steps.map(\.duration), [0.06, 0.5])
        XCTAssertEqual(steps.map(\.easesOut), [false, true])
        XCTAssertEqual(steps.map(\.scale), [1.0, 1.0], "The afterglow only brightens; it never moves")
    }
}
