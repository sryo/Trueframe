import SwiftUI

/// The app's shared animation vocabulary.
enum Motion {
    static let press = Animation.snappy(duration: 0.16)
    static let select = Animation.smooth(duration: 0.28)
    static let dismiss = Animation.easeOut(duration: 0.15)
    static let glass = Animation.spring(duration: 0.4, bounce: 0.3)
    static let snap = Animation.snappy(duration: 0.22)
    /// Stands in for movement when Reduce Motion is on.
    static let fade = Animation.easeOut(duration: 0.2)

    /// A resting heart, 52 bpm.
    static let restingBeatInterval: Duration = .seconds(60.0 / 52)
}
