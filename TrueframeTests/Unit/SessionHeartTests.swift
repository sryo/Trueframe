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

final class LandingBeatTests: XCTestCase {

    func testLandingBeat_startsDarkPeaksBrightAndSettlesAtRest() {
        let resting = HeartbeatKeyframes(isNearFullMoon: false)
        let steps = SessionHeart.landingBeat(settlingTo: resting)

        XCTAssertEqual(SessionHeart.landingStart, 0)
        let opacities = steps.map(\.opacity)
        XCTAssertEqual(opacities.count, 4)
        XCTAssertEqual(opacities[0], 0.9, accuracy: 1e-9)
        XCTAssertEqual(opacities[1], 0.30 + 0.35 * 0.60, accuracy: 1e-9)
        XCTAssertEqual(opacities[2], 0.9 * 0.85, accuracy: 1e-9)
        XCTAssertEqual(opacities[3], resting.restingOpacity, accuracy: 1e-9)
    }

    func testLandingBeat_keepsTheLubDubRhythmAndSwell() {
        let resting = HeartbeatKeyframes(isNearFullMoon: true)
        let steps = SessionHeart.landingBeat(settlingTo: resting)

        XCTAssertEqual(steps.map(\.duration), resting.steps.map(\.duration))
        XCTAssertEqual(steps.map(\.scale), resting.steps.map(\.scale))
        XCTAssertEqual(steps.map(\.easesOut), resting.steps.map(\.easesOut))
        XCTAssertEqual(steps.last?.opacity, 0.5)
    }
}
