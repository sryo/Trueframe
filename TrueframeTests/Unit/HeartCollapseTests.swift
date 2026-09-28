import XCTest
@testable import Trueframe

final class HeartCollapseTests: XCTestCase {

    private let all7 = Array(repeating: true, count: 7)

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
        XCTAssertEqual(pose.scale, 0.04, accuracy: 1e-9)
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
        XCTAssertEqual(HeartCollapse.absorbed(at: 0, kept: all7), 0)
        XCTAssertEqual(HeartCollapse.absorbed(at: HeartCollapse.fallTime + 0.001, kept: all7), 1.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.absorbed(at: HeartCollapse.landed, kept: all7), 1, accuracy: 1e-9)
    }

    func testCore_wobblesAfterALandingAndSettles() {
        let landing = HeartCollapse.fallTime
        XCTAssertEqual(HeartCollapse.wobble(at: landing, kept: [true]), 0, accuracy: 1e-9)
        XCTAssertNotEqual(HeartCollapse.wobble(at: landing + 0.05, kept: [true]), 0)
        XCTAssertEqual(HeartCollapse.wobble(at: landing + 1, kept: [true]), 0, accuracy: 1e-3)
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
        XCTAssertGreaterThan(HeartCollapse.finished - HeartCollapse.burstStart, BurstField.duration - 1e-9)
    }
    func testAbsorbed_countsOnlyKeptPhotos() {
        let kept = [false, true, false]
        let everyoneDone = HeartCollapse.landed
        XCTAssertEqual(HeartCollapse.absorbed(at: everyoneDone, kept: kept), 1, accuracy: 1e-9,
                       "One keeper landing fills the heart when it's the only keeper")
        XCTAssertEqual(HeartCollapse.absorbed(at: HeartCollapse.fallTime + 0.001, kept: kept), 1, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.absorbed(at: HeartCollapse.fallTime - 0.001, kept: kept), 0)
    }

    func testWobble_ignoresDroppedPhotos() {
        XCTAssertEqual(HeartCollapse.wobble(at: HeartCollapse.fallTime + 0.05, kept: [false]), 0)
    }

    func testSling_followsTheSameFallUntilItEscapes() {
        let from = CGPoint(x: 90, y: -280)
        for x in [0.0, 0.3, 0.6] {
            let sling = HeartCollapse.sling(from: from, fanRotation: 0.2, progress: x)
            let fall = HeartCollapse.infall(from: from, fanRotation: 0.2, progress: x)
            XCTAssertEqual(sling.offset.x, fall.offset.x, accuracy: 1e-9)
            XCTAssertEqual(sling.offset.y, fall.offset.y, accuracy: 1e-9)
            XCTAssertEqual(sling.opacity, 1)
        }
    }

    func testSling_isContinuousAtTheEscape() {
        let from = CGPoint(x: 90, y: -280)
        let at = HeartCollapse.sling(from: from, fanRotation: 0, progress: HeartCollapse.slingEscape)
        let after = HeartCollapse.sling(from: from, fanRotation: 0, progress: HeartCollapse.slingEscape + 1e-4)
        XCTAssertEqual(at.offset.x, after.offset.x, accuracy: 0.1)
        XCTAssertEqual(at.offset.y, after.offset.y, accuracy: 0.1)
        XCTAssertEqual(at.opacity, after.opacity, accuracy: 1e-3)
        XCTAssertEqual(at.rotation, after.rotation, accuracy: 1e-3)
    }

    func testSling_isFlungOutwardAfterTheEscape() {
        let from = CGPoint(x: 90, y: -280)
        let distances = [0.62, 0.7, 0.85, 1.0, 1.1].map {
            let o = HeartCollapse.sling(from: from, fanRotation: 0, progress: $0).offset
            return hypot(o.x, o.y)
        }
        XCTAssertEqual(distances, distances.sorted())
        XCTAssertGreaterThan(distances.last! - distances.first!, 100)
    }

    func testSling_spinsExtraOnceItEscapes() {
        let from = CGPoint(x: 90, y: -280)
        let at = HeartCollapse.sling(from: from, fanRotation: 0, progress: 0.62).rotation
        let later = HeartCollapse.sling(from: from, fanRotation: 0, progress: 0.72).rotation
        XCTAssertEqual(later - at, 0.6, accuracy: 1e-9)
    }

    func testSling_losesItsColorOnTheWay() {
        let from = CGPoint(x: 90, y: -280)
        let before = HeartCollapse.sling(from: from, fanRotation: 0, progress: 0.45)
        XCTAssertEqual(before.grayscale, 0)
        XCTAssertEqual(before.brightness, 1)
        let grey = HeartCollapse.sling(from: from, fanRotation: 0, progress: 0.75)
        XCTAssertEqual(grey.grayscale, 1, accuracy: 1e-9)
        XCTAssertEqual(grey.brightness, 0.55, accuracy: 1e-9)
    }

    func testSling_isGoneByTheEnd() {
        let from = CGPoint(x: 90, y: -280)
        XCTAssertEqual(HeartCollapse.sling(from: from, fanRotation: 0, progress: HeartCollapse.slingEnd).opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(HeartCollapse.sling(from: from, fanRotation: 0, progress: 2).opacity, 0)
        XCTAssertLessThan(HeartCollapse.slingEnd * HeartCollapse.fallTime + HeartCollapse.fallStart(index: 0, count: 7),
                          HeartCollapse.burstStart, "Out of sight before the burst")
    }

    func testInfall_keepsItsColor() {
        let pose = HeartCollapse.infall(from: CGPoint(x: 0, y: -300), fanRotation: 0, progress: 0.8)
        XCTAssertEqual(pose.grayscale, 0)
        XCTAssertEqual(pose.brightness, 1)
    }
}
