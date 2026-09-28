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

    init(dim: Double, bright: Double) {
        self.dim = dim
        self.bright = bright
    }

    /// The heart waxes with the moon.
    init(isNearFullMoon: Bool) {
        self = isNearFullMoon ? Self(dim: 0.50, bright: 0.90) : Self(dim: 0.30, bright: 0.60)
    }

    var steps: [Step] {
        [
            Step(opacity: bright, scale: 1.08, duration: 0.06, easesOut: false),
            Step(opacity: dim + 0.35 * (bright - dim), scale: 1.0, duration: 0.14, easesOut: true),
            Step(opacity: bright * 0.85, scale: 1.05, duration: 0.06, easesOut: false),
            Step(opacity: dim, scale: 1.0, duration: 0.70, easesOut: true),
        ]
    }
}
