// One lub-dub of the wordmark heart, as plain values.

import Foundation

struct HeartbeatKeyframes: Equatable {
    struct Step: Equatable {
        let opacity: Double
        let scale: Double
        let duration: TimeInterval
        /// Falling segments ease out so each pulse lands softly.
        let easesOut: Bool
    }

    let dim: Double
    let bright: Double

    /// The heart waxes with the moon.
    init(isNearFullMoon: Bool) {
        (dim, bright) = isNearFullMoon ? (0.50, 0.90) : (0.30, 0.60)
    }

    var restingOpacity: Double { dim }
    var restingScale: Double { 1.0 }

    var steps: [Step] {
        [
            Step(opacity: bright, scale: 1.08, duration: 0.06, easesOut: false),
            Step(opacity: dim + 0.35 * (bright - dim), scale: 1.0, duration: 0.14, easesOut: true),
            Step(opacity: bright * 0.85, scale: 1.05, duration: 0.06, easesOut: false),
            Step(opacity: dim, scale: 1.0, duration: 0.70, easesOut: true),
        ]
    }

    var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }
}
