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
        var scaleX: CGFloat
        var scaleY: CGFloat
        var opacity: Double
    }

    static let fallTime = 0.55
    static let landed = 0.86
    static let squeezeEnd = 0.98
    static let burstStart = 1.08
    /// Home rises behind the sparks, so there's no dead air after the burst.
    static let handoff = burstStart + 0.15
    static let finished = burstStart + BurstField.duration

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
            scaleX: scale * stretch,
            scaleY: scale / stretch,
            opacity: x > 0.85 ? 1 - (x - 0.85) / 0.15 : 1
        )
    }

    /// The share of the photos that have landed.
    static func absorbed(at time: Double, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let landedCount = (0..<count).filter { progress(at: time, index: $0, count: count) >= 1 }.count
        return CGFloat(landedCount) / CGFloat(count)
    }

    /// A damped wobble for each landing, as a fraction of the heart's size.
    static func wobble(at time: Double, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let sum = (0..<count).reduce(0.0) { sum, index in
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
