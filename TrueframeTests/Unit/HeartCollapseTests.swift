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

    /// Every fan start in a 7-photo fan, seen from a heart in the lower left.
    private var fanStarts: [CGPoint] {
        let heart = CGPoint(x: 101, y: 753)
        let center = CGPoint(x: 195, y: 422)
        return FanLayout.slots(count: 7).map {
            CGPoint(x: center.x + $0.offset.width - heart.x, y: center.y + $0.offset.height - heart.y)
        }
    }

    private let lanes = HeartCollapse.slingLanes.indices

    /// The demo's curation: every third photo dropped, starting with the second.
    private func demoVerdict(_ count: Int) -> [Bool] { (0..<count).map { $0 % 3 != 1 } }

    /// Every way a fan of 1 to 7 can split into kept and dropped with at least one kept.
    private var verdicts: [[Bool]] {
        (1...7).flatMap { count in
            (1..<(1 << count)).map { mask in (0..<count).map { mask & (1 << $0) != 0 } }
        }
    }

    private func pose(_ from: CGPoint, _ u: Double, lane: Int = 0) -> HeartCollapse.Infall {
        HeartCollapse.sling(from: from, fanRotation: 0, progress: u, lane: lane)
    }

    private func sweep(_ from: CGPoint, lane: Int, through end: Double = 1.6, step: Double = 0.001) -> [(u: Double, pose: HeartCollapse.Infall)] {
        stride(from: 0, through: end, by: step).map { ($0, HeartCollapse.sling(from: from, fanRotation: 0.2, progress: $0, lane: lane)) }
    }

    private func offset(_ from: CGPoint, _ u: Double, lane: Int = 0) -> CGPoint {
        pose(from, u, lane: lane).offset
    }

    private func heading(_ from: CGPoint, at u: Double, lane: Int = 0) -> Double {
        let a = offset(from, u - 0.002, lane: lane), b = offset(from, u + 0.002, lane: lane)
        return atan2(b.y - a.y, b.x - a.x)
    }

    private func speed(_ from: CGPoint, at u: Double, lane: Int = 0) -> CGFloat {
        let a = offset(from, u - 0.002, lane: lane), b = offset(from, u + 0.002, lane: lane)
        return hypot(b.x - a.x, b.y - a.y) / 0.004
    }

    /// Progress `seconds` after the closest pass.
    private func after(_ seconds: Double) -> Double { 1 + seconds / HeartCollapse.slingFall }

    func testSling_startsExactlyWhereTheFanLeftIt() {
        let from = CGPoint(x: 90, y: -280)
        for lane in lanes {
            for u in [0.0, -0.3] {
                let pose = HeartCollapse.sling(from: from, fanRotation: 0.3, progress: u, lane: lane)
                XCTAssertEqual(pose.offset.x, 90, accuracy: 1e-9)
                XCTAssertEqual(pose.offset.y, -280, accuracy: 1e-9)
                XCTAssertEqual(pose.rotation, 0.3, accuracy: 1e-9)
                XCTAssertEqual(pose.scaleX, 1, accuracy: 1e-9)
                XCTAssertEqual(pose.scaleY, 1, accuracy: 1e-9)
                XCTAssertEqual(pose.opacity, 1)
                XCTAssertEqual(pose.grayscale, 0)
            }
        }
    }

    func testSlingPass_fallsOnTheKeptPhotosClockAndStartsFromTheFan() {
        XCTAssertEqual(HeartCollapse.slingFall, HeartCollapse.fallTime, "The same gravity as the kept fall")
        for kept in verdicts {
            for index in kept.indices where !kept[index] {
                let pass = HeartCollapse.slingPass(index: index, kept: kept)
                XCTAssertEqual(HeartCollapse.slingProgress(at: pass, index: index, kept: kept), 1, accuracy: 1e-9)
                XCTAssertLessThanOrEqual(HeartCollapse.slingProgress(at: 0, index: index, kept: kept), 1e-9,
                                         "\(kept): \(index) starts from the fan, not partway down")
                XCTAssertGreaterThanOrEqual(pass, HeartCollapse.fallTime - 1e-9, "\(kept): no sooner than a kept photo could land")
                XCTAssertLessThanOrEqual(pass, HeartCollapse.slingLatest + 1e-9)
            }
        }
    }

    func testSlingPass_spreadsDropsApartInTimeAndPlace() {
        for kept in verdicts {
            let drops = kept.indices.filter { !kept[$0] }
            for (a, b) in zip(drops, drops.dropFirst()) {
                XCTAssertGreaterThan(HeartCollapse.slingPass(index: b, kept: kept), HeartCollapse.slingPass(index: a, kept: kept),
                                     "\(kept): \(a) and \(b) pass at different moments")
                XCTAssertNotEqual(HeartCollapse.slingLane(index: a, kept: kept), HeartCollapse.slingLane(index: b, kept: kept),
                                  "\(kept): and on different tracks")
            }
        }
        let demo = demoVerdict(7)
        XCTAssertGreaterThanOrEqual(HeartCollapse.slingPass(index: 4, kept: demo) - HeartCollapse.slingPass(index: 1, kept: demo), 0.03,
                                    "Two drops in a full fan pass a couple of frames apart")
    }

    func testSling_spiralsInTheSameWayAsTheKeptPhotos() {
        for from in fanStarts {
            for lane in lanes {
                var last = atan2(from.y, from.x), lastDistance = hypot(from.x, from.y)
                for u in stride(from: 0.05, through: 1.0, by: 0.05) {
                    let o = offset(from, u, lane: lane)
                    let angle = atan2(o.y, o.x)
                    XCTAssertGreaterThanOrEqual(atan2(sin(angle - last), cos(angle - last)), -1e-9, "Clockwise like the kept fall at \(u)")
                    XCTAssertLessThan(hypot(o.x, o.y), lastDistance, "Closing in at \(u)")
                    last = angle
                    lastDistance = hypot(o.x, o.y)
                }
            }
            XCTAssertEqual(pose(from, 0.5).scale, HeartCollapse.infall(from: from, fanRotation: 0, progress: 0.5).scale, accuracy: 0.12)
        }
    }

    func testSling_movesWithoutJumps() {
        for from in fanStarts {
            for lane in lanes {
                let poses = sweep(from, lane: lane)
                for (a, b) in zip(poses, poses.dropFirst()) {
                    XCTAssertLessThan(hypot(b.pose.offset.x - a.pose.offset.x, b.pose.offset.y - a.pose.offset.y), 8, "at \(b.u)")
                    XCTAssertLessThan(abs(b.pose.rotation - a.pose.rotation), 0.05, "at \(b.u)")
                    XCTAssertLessThan(abs(b.pose.scaleX - a.pose.scaleX), 0.02, "at \(b.u)")
                    XCTAssertLessThan(abs(b.pose.scaleY - a.pose.scaleY), 0.02, "at \(b.u)")
                    XCTAssertLessThan(abs(b.pose.opacity - a.pose.opacity), 0.01, "at \(b.u)")
                    XCTAssertLessThan(abs(b.pose.grayscale - a.pose.grayscale), 0.02, "at \(b.u)")
                    XCTAssertLessThan(abs(b.pose.brightness - a.pose.brightness), 0.01, "at \(b.u)")
                }
            }
        }
    }

    func testSling_isSmoothThroughItsClosestPass() {
        for from in fanStarts {
            for lane in lanes {
                let before = pose(from, 1 - 1e-7, lane: lane)
                let after = pose(from, 1 + 1e-7, lane: lane)
                XCTAssertEqual(before.offset.x, after.offset.x, accuracy: 0.01)
                XCTAssertEqual(before.offset.y, after.offset.y, accuracy: 0.01)
                XCTAssertEqual(before.rotation, after.rotation, accuracy: 1e-4)
                XCTAssertEqual(before.scaleX, after.scaleX, accuracy: 1e-4)
                XCTAssertEqual(before.scaleY, after.scaleY, accuracy: 1e-4)
                let kink = heading(from, at: 1 + 0.003, lane: lane) - heading(from, at: 1 - 0.003, lane: lane)
                XCTAssertEqual(atan2(sin(kink), cos(kink)), 0, accuracy: 0.2, "Curves through, no kink")
                XCTAssertEqual(speed(from, at: 1 - 0.003, lane: lane) / speed(from, at: 1 + 0.003, lane: lane), 1, accuracy: 0.08, "No lurch in speed")
                let spinIn = pose(from, 1, lane: lane).rotation - pose(from, 1 - 1e-4, lane: lane).rotation
                let spinOut = pose(from, 1 + 1e-4, lane: lane).rotation - pose(from, 1, lane: lane).rotation
                XCTAssertEqual(spinIn / spinOut, 1, accuracy: 0.01, "Spin carries through")
            }
        }
    }

    func testSling_passesCloseButNeverTouchesTheHeart() {
        for from in fanStarts {
            for lane in lanes {
                let miss = HeartCollapse.slingLanes[lane].miss
                let poses = sweep(from, lane: lane).filter { $0.pose.opacity > 0 }
                let clearances = poses.map { step in
                    let o = step.pose.offset
                    let reach = FanLayout.photoSize / 2 * hypot(step.pose.scaleX, step.pose.scaleY)
                    return hypot(o.x, o.y) - reach - HeartCollapse.coreCap
                }
                XCTAssertGreaterThan(clearances.min() ?? 0, 4, "Misses")
                let closest = poses.map { hypot($0.pose.offset.x, $0.pose.offset.y) }.min() ?? 0
                XCTAssertEqual(closest, miss, accuracy: 0.5)
                let o = offset(from, 1, lane: lane)
                XCTAssertEqual(hypot(o.x, o.y), miss, accuracy: 1e-6, "Closest at the pass")
                let leaving = poses.filter { $0.u >= 1 }.map { hypot($0.pose.offset.x, $0.pose.offset.y) }
                for (a, b) in zip(leaving, leaving.dropFirst()) { XCTAssertGreaterThan(b, a, "Only pulls away once past") }
            }
        }
    }

    func testSling_isFastestAtThePassThenIsFlungNotDropped() {
        let frame = 1.0 / 60
        for from in fanStarts {
            for lane in lanes {
                let pass = speed(from, at: 1, lane: lane)
                XCTAssertGreaterThan(pass, speed(from, at: 0.85, lane: lane))
                XCTAssertLessThan(pass, 2.5 * speed(from, at: 0.85, lane: lane), "A whip, not a teleport")
                // As seen at 60fps: how far it moves each frame
                func step(_ k: Double) -> CGFloat {
                    let a = offset(from, after((k - 1) * frame), lane: lane), b = offset(from, after(k * frame), lane: lane)
                    return hypot(b.x - a.x, b.y - a.y)
                }
                let passing = step(0.5)
                for k in 1...6 {
                    XCTAssertLessThanOrEqual(step(Double(k)), passing * 1.12, "No faster than as it passes")
                    XCTAssertGreaterThan(step(Double(k)), 0.7 * passing, "Still flung \(k) frames after the pass")
                }
                XCTAssertGreaterThan(speed(from, at: after(0.05), lane: lane), speed(from, at: after(0.15), lane: lane), "Easing off, not a rocket")
            }
        }
    }

    func testSling_leavesAtLeastAsFastAsItCameInAtTheSameDistance() {
        for from in fanStarts {
            for lane in lanes {
                let approach = stride(from: 0.3, through: 0.995, by: 0.005).map { u -> (distance: CGFloat, speed: CGFloat) in
                    let o = offset(from, u, lane: lane)
                    return (hypot(o.x, o.y), speed(from, at: u, lane: lane))
                }
                for seconds in stride(from: 0.02, through: 0.15, by: 0.01) {
                    let u = after(seconds)
                    let o = offset(from, u, lane: lane)
                    let distance = hypot(o.x, o.y)
                    guard let incoming = approach.min(by: { abs($0.distance - distance) < abs($1.distance - distance) }) else { continue }
                    XCTAssertGreaterThanOrEqual(speed(from, at: u, lane: lane), incoming.speed,
                                                "The same gravity lets go of it at least as fast, \(Int(distance))pt out")
                }
            }
        }
    }

    func testSling_bendsAroundTheHeartOntoANewHeadingWithoutDoublingBack() {
        for from in fanStarts {
            for lane in lanes {
                let flung = heading(from, at: after(0.12), lane: lane)
                var turn = flung - heading(from, at: 0.8, lane: lane)
                turn = atan2(sin(turn), cos(turn))
                XCTAssertGreaterThan(turn, 80 * .pi / 180, "Bent around the heart, not nudged")
                XCTAssertLessThan(turn, 150 * .pi / 180, "Not a U-turn")
                XCTAssertGreaterThan(flung, -115 * .pi / 180, "Mostly up, with room to fly")
                XCTAssertLessThan(flung, -90 * .pi / 180, "A little left, away from the kept photos")
            }
        }
    }

    func testSling_staysOnScreenAndOnTheLeftOnceFlung() {
        for from in fanStarts {
            for lane in lanes {
                let visible = sweep(from, lane: lane).filter { $0.pose.opacity > 0 }
                XCTAssertLessThanOrEqual(visible.map(\.pose.offset.y).max() ?? 0, 52, "At most about 50pt below the heart, clear of the bottom edge")
                let leaving = visible.filter { $0.u > 1 }
                XCTAssertLessThan(leaving.map(\.pose.offset.x).max() ?? 0, 0, "Left of the heart, away from the kept photos")
                let seen = leaving.filter { $0.pose.opacity > 0.25 }.map(\.pose.offset.x).min() ?? 0
                XCTAssertGreaterThan(seen, -95, "Still on screen while plainly visible, with the heart about 100pt from the left edge")
            }
        }
    }

    func testSling_isSmallerThanAHeroAtThePassAndOnlyShrinksAsItLeaves() {
        for from in fanStarts {
            for lane in lanes {
                let leaving = sweep(from, lane: lane, through: 2).filter { $0.u >= 1 }.map(\.pose)
                for (a, b) in zip(leaving, leaving.dropFirst()) {
                    XCTAssertLessThanOrEqual(b.scaleX, a.scaleX + 1e-12, "Never longer")
                    XCTAssertLessThanOrEqual(b.scaleY, a.scaleY + 1e-12, "Never wider")
                }
                XCTAssertLessThanOrEqual(leaving.first!.scale, 0.14, "A near miss, not the hero landing")
                XCTAssertEqual(leaving.last!.scaleX, 0.095, accuracy: 0.01)
            }
        }
    }

    func testSling_staysInSightLongEnoughToBeSeenLeaving() {
        for from in fanStarts {
            for lane in lanes {
                XCTAssertEqual(pose(from, after(0.05), lane: lane).opacity, 1, "Fully there for three frames after the pass")
                XCTAssertGreaterThan(pose(from, after(0.1), lane: lane).opacity, 0.5, "Still plainly thrown 100ms after")
            }
        }
    }

    func testSling_isGoneBeforeTheHeartSqueezes() {
        XCTAssertEqual(pose(fanStarts[0], HeartCollapse.slingEnd).opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(pose(fanStarts[0], 3).opacity, 0)
        let clearOfTheSqueeze = HeartCollapse.landed - 6.0 / 60
        for kept in verdicts {
            for index in kept.indices where !kept[index] {
                let u = HeartCollapse.slingProgress(at: clearOfTheSqueeze, index: index, kept: kept)
                XCTAssertGreaterThanOrEqual(u, HeartCollapse.slingEnd, "\(kept): \(index) is gone six frames before the heart squeezes")
            }
        }
        let demo = demoVerdict(3)
        let lastLanding = HeartCollapse.fallStart(index: 0, count: 3) + HeartCollapse.fallTime
        XCTAssertGreaterThanOrEqual(HeartCollapse.slingProgress(at: lastLanding - 6.0 / 60, index: 1, kept: demo), HeartCollapse.slingEnd,
                                    "Gone six frames before the kept photos light the heart up")
    }

    func testSling_keepsItsColorUntilItMissesThenGreysWithoutGoingDark() {
        for lane in lanes {
            let from = fanStarts[3]
            let approaching = pose(from, 0.9, lane: lane)
            XCTAssertEqual(approaching.grayscale, 0)
            XCTAssertEqual(approaching.brightness, 1, accuracy: 1e-3)
            let passing = pose(from, 1, lane: lane)
            XCTAssertGreaterThan(passing.grayscale, 0)
            XCTAssertLessThan(passing.grayscale, 0.5)
            let rejected = pose(from, 1.08, lane: lane)
            XCTAssertGreaterThan(rejected.opacity, 0.95, "Seen being turned away")
            let flung = pose(from, 1.2, lane: lane)
            XCTAssertEqual(flung.grayscale, 1, accuracy: 1e-9)
            XCTAssertEqual(flung.brightness, 0.75, accuracy: 0.01)
            let dimmest = sweep(from, lane: lane).map(\.pose.brightness).min() ?? 0
            XCTAssertGreaterThanOrEqual(dimmest, 0.75 - 1e-9, "Fades away rather than blinking out")
        }
    }

    func testSling_stretchesMostAsItPassesTheHeart() {
        let from = fanStarts[3]
        func stretch(_ u: Double) -> CGFloat {
            let pose = HeartCollapse.sling(from: from, fanRotation: 0, progress: u)
            return pose.scaleX / pose.scaleY
        }
        XCTAssertGreaterThan(stretch(1), stretch(0.8))
        XCTAssertGreaterThan(stretch(1), stretch(1.05))
        XCTAssertLessThanOrEqual(stretch(1), 1.3 * 1.3 + 1e-9, "At most 1.3x along its path")
        XCTAssertEqual(stretch(after(0.1)), 1, accuracy: 0.1, "Relaxed within about six frames")
    }

    func testSling_spinsFastestAsItPassesTheHeartThenSettlesIntoATumble() {
        let from = fanStarts[3]
        func spin(_ u: Double) -> Double {
            (pose(from, u + 0.005).rotation - pose(from, u - 0.005).rotation) / 0.01 / HeartCollapse.slingFall
        }
        XCTAssertGreaterThan(spin(1), spin(0.8))
        XCTAssertGreaterThan(spin(1), spin(after(0.05)))
        XCTAssertLessThan(spin(1), 30, "Readable at 60fps, not a strobe")
        XCTAssertGreaterThan(spin(after(0.25)), 0, "Still turning the same way")
        XCTAssertLessThan(spin(after(0.25)), 0.3 * spin(1), "A slow tumble by the time it fades")
    }

    func testInfall_keepsItsColor() {
        let pose = HeartCollapse.infall(from: CGPoint(x: 0, y: -300), fanRotation: 0, progress: 0.8)
        XCTAssertEqual(pose.grayscale, 0)
        XCTAssertEqual(pose.brightness, 1)
    }
}
