import CoreGraphics
import Foundation

/// What comes out of the heart: sparks in the session's own colors, a soft
/// flash, and one shockwave ring. Times are seconds from the burst.
enum BurstField {
    struct Spark: Equatable, Sendable {
        var angle: Double
        /// Points per second at the start.
        var speed: Double
        var life: Double
        var radius: CGFloat
    }

    struct Ring: Equatable {
        var radius: CGFloat
        var opacity: Double
        var lineWidth: CGFloat
    }

    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    static let duration = 1.15
    static let glowRadius: CGFloat = 60
    static let ringDelay = 0.22
    static let ringTime = 0.9
    /// Dark photos would make sparks nobody sees against black.
    static let minimumTintBrightness = 0.75

    static let sparks = makeSparks()

    /// Seeded, so it's the same burst every time.
    static func makeSparks() -> [Spark] {
        (0..<70).map { index in
            Spark(
                angle: random(index, salt: 9) * 2 * .pi,
                speed: 160 + random(index, salt: 10) * 360,
                life: 0.6 + random(index, salt: 12) * 0.5,
                radius: 1 + CGFloat(random(index, salt: 11)) * 1.6
            )
        }
    }

    private static func lifetime(of spark: Spark, at t: Double) -> Double {
        min(max(t / spark.life, 0), 1)
    }

    /// Decelerating outward, like something thrown through thick air.
    static func distance(of spark: Spark, at t: Double) -> CGFloat {
        let k = lifetime(of: spark, at: t)
        return CGFloat(spark.speed * spark.life * (1 - pow(1 - k, 3)) / 1.6)
    }

    static func position(of spark: Spark, at t: Double, around center: CGPoint) -> CGPoint {
        let d = distance(of: spark, at: t)
        return CGPoint(x: center.x + CGFloat(cos(spark.angle)) * d, y: center.y + CGFloat(sin(spark.angle)) * d)
    }

    static func radius(of spark: Spark, at t: Double) -> CGFloat {
        spark.radius * (1 - 0.5 * CGFloat(lifetime(of: spark, at: t)))
    }

    static func opacity(of spark: Spark, at t: Double) -> Double {
        let k = lifetime(of: spark, at: t)
        guard k < 1 else { return 0 }
        return (1 - k) * min(max(t / 0.05, 0), 1)
    }

    static func glowOpacity(at t: Double) -> Double {
        max(0, 0.25 * (1 - t / 0.35))
    }

    static func ring(at t: Double, cover: CGFloat) -> Ring? {
        let x = (t - ringDelay) / ringTime
        guard x > 0, x < 1 else { return nil }
        return Ring(
            radius: 2 + cover * 0.9 * CGFloat(1 - pow(1 - x, 2.2)),
            opacity: 0.4 * (1 - x),
            lineWidth: 2 * (1 - 0.6 * CGFloat(x))
        )
    }

    /// How far the furthest corner of `size` is from `center`.
    static func cover(from center: CGPoint, in size: CGSize) -> CGFloat {
        [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - center.x, $0.y - center.y) }
            .max() ?? 0
    }

    /// Keeps the photo's hue but lifts it bright enough to read on black.
    static func tint(for color: RGB) -> RGB {
        let brightest = max(color.red, color.green, color.blue)
        guard brightest < minimumTintBrightness else { return color }
        guard brightest > 0 else {
            return RGB(red: minimumTintBrightness, green: minimumTintBrightness, blue: minimumTintBrightness)
        }
        let lift = minimumTintBrightness / brightest
        return RGB(red: color.red * lift, green: color.green * lift, blue: color.blue * lift)
    }

    /// Uniform in 0..<1, from the index and salt alone.
    private static func random(_ index: Int, salt: UInt64) -> Double {
        var z = UInt64(truncatingIfNeeded: index) &* 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
