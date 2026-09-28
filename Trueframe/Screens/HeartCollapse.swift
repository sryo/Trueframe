import SwiftUI

/// How the fanned photos fall into the heart, and how the heart takes them in
/// before it bursts. Times are seconds from the start of the fall.
///
/// Mass reads as brightness, not size: the heart never outgrows a few points,
/// so the one big change on screen is the burst.
enum HeartCollapse {
    struct Infall: Equatable {
        /// From the heart.
        var offset: CGPoint
        /// The photo's own turn, in radians.
        var rotation: Double
        /// The axis it's stretched along: its direction of travel.
        var direction: Double
        var scale: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat
        var opacity: Double
        var grayscale: Double = 0
        /// Multiplies the photo's color.
        var brightness: Double = 1
    }

    static let fallTime = 0.55
    static let landed = 0.86
    static let squeezeEnd = 0.98
    static let burstStart = 1.08
    /// Home rises behind the sparks, so there's no dead air after the burst.
    static let handoff = burstStart + 0.15
    static let finished = burstStart + BurstField.duration

    /// How long a dropped photo takes to reach its closest pass: the same
    /// as a kept photo's fall, so both feel the same gravity.
    static let slingFall = fallTime
    /// Where a dropped photo passes the heart: how close to its center, in
    /// points, and where around it, in radians clockwise from the right. Just
    /// past its lower left, so it comes in under the heart. `heading` is where
    /// it's flung: up the left margin, clear of the kept photos coming in from
    /// the right. Drops take turns between the two, so ones that pass close
    /// together visibly follow different tracks.
    static let slingLanes: [(miss: CGFloat, angle: Double, heading: Double)] = [
        (36, 140 * Double.pi / 180, -94 * Double.pi / 180),
        (44, 132 * Double.pi / 180, -91 * Double.pi / 180),
    ]
    /// Drops pass within this window, in turn: from when a kept photo in the
    /// fan's middle would land, until the last one can still be gone well
    /// before the heart squeezes.
    static let slingEarliest = fallTime
    static let slingLatest = 0.585
    static let slingFade = 1.1
    static let slingEnd = 1.31

    static let coreStart: CGFloat = 3
    static let coreCap: CGFloat = 6
    static let speck: CGFloat = 1.2

    /// The outer photos start falling last, so the fan closes from its middle.
    static func fallStart(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let mid = Double(count - 1) / 2
        return 0.28 * pow(abs(Double(index) - mid) / mid, 0.7)
    }

    static func progress(at time: Double, index: Int, count: Int) -> Double {
        (time - fallStart(index: index, count: count)) / fallTime
    }

    /// Gravity pulls it in, accelerating to the end, and it spins up as it
    /// closes like a skater pulling their arms in.
    static func path(from start: CGPoint, progress x: Double) -> CGPoint {
        let fall = x * x * x
        let spin = 2.2 * fall
        let k = 1 - fall
        let px = start.x * k, py = start.y * k
        return CGPoint(x: px * cos(spin) - py * sin(spin), y: px * sin(spin) + py * cos(spin))
    }

    static func infall(from start: CGPoint, fanRotation: Double, progress: Double) -> Infall {
        let x = min(max(progress, 0), 1)
        let here = path(from: start, progress: x)
        let ahead = path(from: start, progress: min(x + 0.02, 1))
        let scale = max(0.04, 1 - 0.96 * pow(x, 0.8))
        let stretch = 1 + 0.8 * x
        return Infall(
            offset: here,
            rotation: fanRotation + 1.5 * 2.2 * x * x * x,
            direction: ahead == here ? 0 : atan2(ahead.y - here.y, ahead.x - here.x),
            scale: scale,
            scaleX: scale * stretch,
            scaleY: scale / stretch,
            opacity: x > 0.85 ? 1 - (x - 0.85) / 0.15 : 1
        )
    }

    /// Drops pass in turn, left to right across the fan, spread over the window.
    static func slingPass(index: Int, kept: [Bool]) -> Double {
        let drops = kept.indices.filter { !kept[$0] }
        guard drops.count > 1, let rank = drops.firstIndex(of: index) else { return slingEarliest }
        return slingEarliest + (slingLatest - slingEarliest) * Double(rank) / Double(drops.count - 1)
    }

    /// Which of `slingLanes` a dropped photo takes.
    static func slingLane(index: Int, kept: [Bool]) -> Int {
        (kept.indices.filter { !kept[$0] }.firstIndex(of: index) ?? 0) % slingLanes.count
    }

    /// 1 at its closest pass.
    static func slingProgress(at time: Double, index: Int, kept: [Bool]) -> Double {
        (time - slingPass(index: index, kept: kept)) / slingFall + 1
    }

    /// A dropped photo spirals in with the rest but aimed a little wide, so
    /// it whips around under the heart instead of into it and is flung up and
    /// away, losing its color as it goes.
    static func sling(from start: CGPoint, fanRotation: Double, progress u: Double, lane: Int = 0) -> Infall {
        let u = max(u, 0)
        let lane = slingLanes[lane % slingLanes.count]
        let here = flyby(from: start, progress: u, lane: lane)
        let behind = flyby(from: start, progress: max(u - 0.005, 0), lane: lane)
        let after = u - 1

        // Never bigger than a near miss should look. Once past, `minor` (its
        // width across its path) and the stretch both only ease off, so it
        // never looks to be coming back toward the viewer
        let pass = 0.13, peakStretch = 0.3
        let scale: Double, stretch: Double
        if u <= 1 {
            scale = pass + (1 - pass) * (1 - pow(u, 0.8))
            stretch = 1 + peakStretch * u
        } else {
            stretch = 1 + peakStretch * exp(-after / 0.09)
            let minor = pass / (1 + peakStretch) * (0.95 + 0.05 * exp(-after / 0.15))
            scale = minor * stretch
        }
        let grey = smoothstep(min(max((u - 0.97) / 0.15, 0), 1))
        let fade = smoothstep(min(max((u - slingFade) / (slingEnd - slingFade), 0), 1))
        return Infall(
            offset: here,
            rotation: fanRotation + slingSpin(u),
            direction: behind == here ? 0 : atan2(here.y - behind.y, here.x - behind.x),
            scale: CGFloat(scale),
            scaleX: CGFloat(scale * stretch),
            scaleY: CGFloat(scale / stretch),
            opacity: 1 - fade,
            grayscale: grey,
            brightness: 1 - 0.25 * grey
        )
    }

    /// How far a dropped photo has turned. It spins up on the way in, a
    /// little faster than a kept photo lands, then the spin dies down to a
    /// slow tumble: `peak` and `tumble` are rates per unit of progress.
    private static func slingSpin(_ u: Double) -> Double {
        let peak = 13.0, tumble = 2.4, settle = 0.12
        if u <= 1 { return peak / 3 * u * u * u }
        let after = u - 1
        return peak / 3 + tumble * after + (peak - tumble) * settle * (1 - exp(-after / settle))
    }

    /// How the approach's gravity bends it: `atan(s / miss)` alone would be
    /// a straight line past the heart, and the second term adds a whip within
    /// a few tens of points of the pass.
    private static let bendNear = 1.05, bendWhip = 0.45, whipWidth = 22.0
    private static let approachEase = 2.5

    /// Where the dropped photo is, relative to the heart.
    private static func flyby(
        from start: CGPoint, progress u: Double, lane: (miss: CGFloat, angle: Double, heading: Double)
    ) -> CGPoint {
        let miss = Double(lane.miss)
        let startDistance = max(Double(hypot(start.x, start.y)), miss + 1)
        let reach = (startDistance * startDistance - miss * miss).squareRoot()
        guard u <= 1 else { return escape(after: u - 1, reach: reach, lane: lane) }

        // `along` is its signed distance to the point of closest approach and
        // the heart sits `miss` off that line, so it can never get nearer
        let along = reach * (1 - pow(u, approachEase))
        let distance = (along * along + miss * miss).squareRoot()
        func bend(_ s: Double) -> Double { bendNear * atan(s / miss) + bendWhip * atan(s / whipWidth) }
        let startAngle = atan2(Double(start.y), Double(start.x))
        var total = (lane.angle - startAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if total < 0 { total += 2 * .pi }
        // The rest of the turn from the fan to the pass, as a spiral that
        // fades out before the pass so the two join smoothly
        let spiral = total - bend(reach)
        let angle = startAngle + total - bend(along) - spiral * pow(along / reach, 2)
        return CGPoint(x: distance * cos(angle), y: distance * sin(angle))
    }

    /// Past the pass it's thrown: it leaves at the pass's speed and eases to a
    /// little over half of it, still faster than it came in at the same
    /// distance, while its heading swings from the pass onto the lane's.
    ///
    /// The heading turns by `turn` over an e-folding `length` of path, chosen
    /// so the curve bends exactly as sharply as the approach did at the pass.
    private static func escape(after e: Double, reach: Double, lane: (miss: CGFloat, angle: Double, heading: Double)) -> CGPoint {
        let miss = Double(lane.miss)
        // How fast the approach sweeps around the heart per point of `along`
        // at the pass, and the curvature and speed that gives there
        let sweep = bendNear / miss + bendWhip / whipWidth
        let curvature = (1 - 1 / pow(miss * sweep, 2)) / miss
        let passSpeed = approachEase * reach * miss * sweep
        let held = 0.58, ease = 0.1
        let travelled = passSpeed * (held * e + (1 - held) * ease * (1 - exp(-e / ease)))

        let passHeading = lane.angle + .pi / 2
        var turn = (lane.heading - passHeading).truncatingRemainder(dividingBy: 2 * .pi)
        if turn <= -.pi { turn += 2 * .pi } else if turn > .pi { turn -= 2 * .pi }
        let length = turn / curvature
        func heading(_ l: Double) -> Double { passHeading + turn * (1 - exp(-l / length)) }

        // Simpson's rule along the path
        let steps = max(8, 2 * Int((travelled / 12).rounded(.up)))
        let h = travelled / Double(steps)
        var x = 0.0, y = 0.0
        for i in 0...steps {
            let weight: Double = i == 0 || i == steps ? 1 : (i % 2 == 1 ? 4 : 2)
            let a = heading(Double(i) * h)
            x += weight * cos(a)
            y += weight * sin(a)
        }
        return CGPoint(x: miss * cos(lane.angle) + x * h / 3, y: miss * sin(lane.angle) + y * h / 3)
    }

    private static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// The share of the kept photos that have landed; dropped ones never do.
    static func absorbed(at time: Double, kept: [Bool]) -> CGFloat {
        let keepers = kept.indices.filter { kept[$0] }
        guard !keepers.isEmpty else { return 0 }
        let landed = keepers.filter { progress(at: time, index: $0, count: kept.count) >= 1 }.count
        return CGFloat(landed) / CGFloat(keepers.count)
    }

    /// A damped wobble for each landing, as a fraction of the heart's size.
    static func wobble(at time: Double, kept: [Bool]) -> CGFloat {
        let count = kept.count
        guard count > 0 else { return 0 }
        let sum = kept.indices.filter { kept[$0] }.reduce(0.0) { sum, index in
            let tau = time - fallStart(index: index, count: count) - fallTime
            guard tau >= 0 else { return sum }
            return sum + 4 / Double(count) * exp(-9 * tau) * sin(26 * tau)
        }
        return CGFloat(min(max(sum, -0.08), 0.08))
    }

    /// Held small just before the burst.
    static func shiver(at time: Double) -> CGFloat {
        guard time > squeezeEnd, time < burstStart else { return 0 }
        return 0.12 * CGFloat(sin(190 * time))
    }

    /// Half the heart's width.
    static func coreRadius(at time: Double, absorbed m: CGFloat) -> CGFloat {
        let fed = coreStart + (coreCap - coreStart) * sqrt(min(max(m, 0), 1))
        if time < landed { return fed }
        if time < squeezeEnd {
            let x = (time - landed) / (squeezeEnd - landed)
            return fed - (fed - speck) * CGFloat(x * x * x)
        }
        return speck
    }

    static func coreOpacity(at time: Double, absorbed m: CGFloat) -> Double {
        let fadeIn = min(max(time / 0.15, 0), 1)
        return fadeIn * (0.35 + 0.55 * min(1, Double(m) * 1.3))
    }

    /// The classic heart curve, centered on the origin and `halfWidth` wide each side.
    static func heartPath(halfWidth r: CGFloat) -> Path {
        let s = r / 16
        var path = Path()
        for step in 0...60 {
            let t = Double(step) / 60 * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            // The curve spans -12...17 vertically; the extra 2.5 centers it
            let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) - 2.5
            let point = CGPoint(x: x * s, y: y * s)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
