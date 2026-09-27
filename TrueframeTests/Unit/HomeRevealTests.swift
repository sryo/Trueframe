// Unit tests for the home screen's enter and exit timeline.

import XCTest
@testable import Trueframe

final class HomeRevealTests: XCTestCase {

    // MARK: - Delays

    func testLines_staggerByTwelveHundredthsFromTheStart() {
        XCTAssertEqual(HomeReveal.delay(for: .line(0), after: 0.2), 0.2, accuracy: 1e-9)
        XCTAssertEqual(HomeReveal.delay(for: .line(1), after: 0.2), 0.32, accuracy: 1e-9)
    }

    func testWordmark_followsTheLastLine() {
        let wordmark = HomeReveal.delay(for: .wordmark, after: 0.2)
        XCTAssertEqual(wordmark, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(wordmark, HomeReveal.delay(for: .line(HomeReveal.lines.count - 1), after: 0.2))
    }

    func testControls_arriveLast() {
        XCTAssertEqual(HomeReveal.delay(for: .controls, after: 0.2), 0.7, accuracy: 1e-9)
        XCTAssertEqual(HomeReveal.delay(for: .controls, after: 0.3), 0.8, accuracy: 1e-9)
    }

    func testAllParts_listsBothLinesThenWordmarkThenControls() {
        XCTAssertEqual(HomeReveal.lines, ["hold to your heart", "to capture life"])
        XCTAssertEqual(HomeReveal.Part.all, [.line(0), .line(1), .wordmark, .controls])
    }

    // MARK: - Poses

    func testWaiting_isBelowBlurredAndInvisible() {
        let pose = HomeReveal.pose(for: .waiting, reduceMotion: false)
        XCTAssertEqual(pose, HomeReveal.Pose(opacity: 0, offsetY: 12, blur: 6))
    }

    func testShown_isInPlaceAndSharp() {
        let pose = HomeReveal.pose(for: .shown, reduceMotion: false)
        XCTAssertEqual(pose, HomeReveal.Pose(opacity: 1, offsetY: 0, blur: 0))
    }

    func testLeft_sinksFourPointsAndDissolves() {
        let pose = HomeReveal.pose(for: .left, reduceMotion: false)
        XCTAssertEqual(pose, HomeReveal.Pose(opacity: 0, offsetY: 4, blur: 0))
    }

    func testControls_fadeInWithoutRisingButStillSink() {
        XCTAssertFalse(HomeReveal.Part.controls.rises)
        XCTAssertTrue(HomeReveal.Part.line(0).rises)
        XCTAssertEqual(HomeReveal.pose(for: .waiting, reduceMotion: false, rises: false).offsetY, 0)
        XCTAssertEqual(HomeReveal.pose(for: .waiting, reduceMotion: false, rises: false).blur, 6)
        XCTAssertEqual(HomeReveal.pose(for: .left, reduceMotion: false, rises: false).offsetY, 4)
    }

    func testReduceMotion_onlyFades() {
        for state in [HomeReveal.State.waiting, .shown, .left] {
            let pose = HomeReveal.pose(for: state, reduceMotion: true)
            XCTAssertEqual(pose.offsetY, 0)
            XCTAssertEqual(pose.blur, 0)
        }
        XCTAssertEqual(HomeReveal.pose(for: .shown, reduceMotion: true).opacity, 1)
        XCTAssertEqual(HomeReveal.pose(for: .waiting, reduceMotion: true).opacity, 0)
    }
}
