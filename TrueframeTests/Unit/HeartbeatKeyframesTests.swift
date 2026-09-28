import XCTest
@testable import Trueframe

final class HeartbeatKeyframesTests: XCTestCase {

    private let ordinary = HeartbeatKeyframes(isNearFullMoon: false)
    private let fullMoon = HeartbeatKeyframes(isNearFullMoon: true)

    func testBrightness_followsTheMoon() {
        XCTAssertEqual(ordinary.dim, 0.30)
        XCTAssertEqual(ordinary.bright, 0.60)
        XCTAssertEqual(fullMoon.dim, 0.50)
        XCTAssertEqual(fullMoon.bright, 0.90)
    }

    func testOpacity_lubPeaksAtBright_dubAtEightyFivePercent() {
        let opacities = ordinary.steps.map(\.opacity)
        XCTAssertEqual(opacities.count, 4)
        XCTAssertEqual(opacities[0], 0.60, accuracy: 1e-9)
        XCTAssertEqual(opacities[1], 0.30 + 0.35 * 0.30, accuracy: 1e-9)
        XCTAssertEqual(opacities[2], 0.60 * 0.85, accuracy: 1e-9)
        XCTAssertEqual(opacities[3], 0.30, accuracy: 1e-9)
    }

    func testOpacity_fullMoonUsesItsOwnRange() {
        let opacities = fullMoon.steps.map(\.opacity)
        XCTAssertEqual(opacities[0], 0.90, accuracy: 1e-9)
        XCTAssertEqual(opacities[1], 0.50 + 0.35 * 0.40, accuracy: 1e-9)
        XCTAssertEqual(opacities[2], 0.90 * 0.85, accuracy: 1e-9)
        XCTAssertEqual(opacities[3], 0.50, accuracy: 1e-9)
    }

    func testScale_swellsOnEachPulseAndRestsAtOne() {
        XCTAssertEqual(ordinary.steps.map(\.scale), [1.08, 1.0, 1.05, 1.0])
    }

    func testDurations_matchTheLubDubRhythm() {
        let durations = ordinary.steps.map(\.duration)
        XCTAssertEqual(durations, [0.06, 0.14, 0.06, 0.70])
    }

    func testTotalDuration_fitsInsideOneBeat() {
        XCTAssertEqual(ordinary.totalDuration, 0.96, accuracy: 1e-9)
        XCTAssertLessThan(.seconds(ordinary.totalDuration), Motion.restingBeatInterval)
    }

    func testEveryPulse_staysBetweenDimAndBright() {
        for step in ordinary.steps {
            XCTAssertGreaterThanOrEqual(step.opacity, ordinary.dim)
            XCTAssertLessThanOrEqual(step.opacity, ordinary.bright)
        }
    }
}

private extension HeartbeatKeyframes {
    var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }
}
