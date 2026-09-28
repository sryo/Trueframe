import XCTest
@testable import Trueframe

final class HeartCollapseTests: XCTestCase {

    func testFallStart_centerFallsFirstAndOuterPhotosLast() {
        let starts = (0..<7).map { HeartCollapse.fallStart(index: $0, count: 7) }
        XCTAssertEqual(starts[3], 0)
        XCTAssertEqual(starts[0], 0.28, accuracy: 1e-9)
        XCTAssertEqual(starts[6], 0.28, accuracy: 1e-9)
        XCTAssertLessThan(starts[3], starts[2])
        XCTAssertLessThan(starts[2], starts[1])
        XCTAssertLessThan(starts[1], starts[0])
        XCTAssertEqual(starts[1], starts[5], accuracy: 1e-9)
    }

    func testFallStart_singlePhotoFallsAtOnce() {
        XCTAssertEqual(HeartCollapse.fallStart(index: 0, count: 1), 0)
    }

    func testInfall_startsExactlyWhereTheFanLeftIt() {
        let from = CGPoint(x: 80, y: -300)
        let pose = HeartCollapse.infall(from: from, fanRotation: 0.3, progress: 0)
        XCTAssertEqual(pose.offset.x, 80, accuracy: 1e-9)
        XCTAssertEqual(pose.offset.y, -300, accuracy: 1e-9)
        XCTAssertEqual(pose.rotation, 0.3, accuracy: 1e-9)
        XCTAssertEqual(pose.scaleX, 1, accuracy: 1e-9)
        XCTAssertEqual(pose.scaleY, 1, accuracy: 1e-9)
        XCTAssertEqual(pose.opacity, 1)
    }

    func testInfall_endsAtTheHeartTinyAndGone() {
        let pose = HeartCollapse.infall(from: CGPoint(x: 80, y: -300), fanRotation: 0.3, progress: 1)
        XCTAssertEqual(pose.offset.x, 0, accuracy: 1e-9)
        XCTAssertEqual(pose.offset.y, 0, accuracy: 1e-9)
        XCTAssertEqual(pose.opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(pose.scaleX * pose.scaleY, 0.04 * 0.04, accuracy: 1e-9)
    }

    func testInfall_accelerates() {
        let from = CGPoint(x: 0, y: -300)
        let early = hypot(HeartCollapse.infall(from: from, fanRotation: 0, progress: 0.25).offset.x,
                          HeartCollapse.infall(from: from, fanRotation: 0, progress: 0.25).offset.y)
        let late = hypot(HeartCollapse.infall(from: from, fanRotation: 0, progress: 0.75).offset.x,
                         HeartCollapse.infall(from: from, fanRotation: 0, progress: 0.75).offset.y)
        XCTAssertGreaterThan(300 - early, 0)
        XCTAssertLessThan(300 - early, early - late, "Covers more ground late in the fall")
    }

    func testInfall_stretchesAlongItsPathAndFadesOnlyAtTheEnd() {
        let pose = HeartCollapse.infall(from: CGPoint(x: 0, y: -300), fanRotation: 0, progress: 0.5)
        XCTAssertGreaterThan(pose.scaleX, pose.scaleY)
        XCTAssertEqual(pose.scaleX / pose.scaleY, 1.4 * 1.4, accuracy: 1e-9)
        XCTAssertEqual(pose.opacity, 1)
        XCTAssertLessThan(HeartCollapse.infall(from: CGPoint(x: 0, y: -300), fanRotation: 0, progress: 0.95).opacity, 1)
    }

    func testCoreRadius_growsWithMassButStaysSmall() {
        let empty = HeartCollapse.coreRadius(at: 0.1, absorbed: 0)
        let half = HeartCollapse.coreRadius(at: 0.5, absorbed: 0.5)
        let full = HeartCollapse.coreRadius(at: 0.85, absorbed: 1)
        XCTAssertEqual(empty, 3, accuracy: 1e-9)
        XCTAssertGreaterThan(half, empty)
        XCTAssertGreaterThan(full, half)
        XCTAssertLessThanOrEqual(full, HeartCollapse.coreCap)
        XCTAssertLessThanOrEqual(HeartCollapse.coreCap, 6)
    }

    func testCoreRadius_sinksToASpeckAfterTheSqueezeWithoutJumping() {
        let before = HeartCollapse.coreRadius(at: HeartCollapse.landed, absorbed: 1)
        XCTAssertEqual(before, HeartCollapse.coreRadius(at: HeartCollapse.landed - 1e-6, absorbed: 1), accuracy: 1e-3)
        let squeezed = HeartCollapse.coreRadius(at: HeartCollapse.squeezeEnd, absorbed: 1)
        XCTAssertEqual(squeezed, HeartCollapse.speck, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.coreRadius(at: 1.05, absorbed: 1), HeartCollapse.speck)
        XCTAssertLessThan(HeartCollapse.speck, 1.5)
    }

    func testCore_absorbsEachPhotoAsItLands() {
        XCTAssertEqual(HeartCollapse.absorbed(at: 0, count: 7), 0)
        XCTAssertEqual(HeartCollapse.absorbed(at: HeartCollapse.fallTime + 0.001, count: 7), 1.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.absorbed(at: HeartCollapse.landed, count: 7), 1, accuracy: 1e-9)
    }

    func testCore_wobblesAfterALandingAndSettles() {
        let landing = HeartCollapse.fallTime
        XCTAssertEqual(HeartCollapse.wobble(at: landing, count: 1), 0, accuracy: 1e-9)
        XCTAssertNotEqual(HeartCollapse.wobble(at: landing + 0.05, count: 1), 0)
        XCTAssertEqual(HeartCollapse.wobble(at: landing + 1, count: 1), 0, accuracy: 1e-3)
    }

    func testCore_shiversOnlyBetweenSqueezeAndBurst() {
        XCTAssertEqual(HeartCollapse.shiver(at: 0.9), 0)
        XCTAssertEqual(HeartCollapse.shiver(at: 1.2), 0)
        let during = stride(from: 0.99, to: 1.07, by: 0.003).map { abs(HeartCollapse.shiver(at: $0)) }
        XCTAssertGreaterThan(during.max() ?? 0, 0.1)
        XCTAssertLessThanOrEqual(during.max() ?? 1, 0.12)
    }

    func testTimeline_handsOffJustAfterTheBurstAndFinishesWhenTheSparksAreGone() {
        XCTAssertEqual(HeartCollapse.burstStart, 1.08, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.handoff, 1.23, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.finished, 1.08 + 1.15, accuracy: 1e-9)
        XCTAssertLessThan(HeartCollapse.handoff, HeartCollapse.finished)
    }
}
