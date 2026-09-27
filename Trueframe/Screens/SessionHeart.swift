import SwiftUI

/// The wordmark heart's values while a session has the screen.
enum SessionHeart {
    static let afterglowResting = 0.12

    /// One faint glow per kept photo.
    static let afterglowPulse: [HeartbeatKeyframes.Step] = [
        .init(opacity: 0.4, scale: 1.0, duration: 0.06, easesOut: false),
        .init(opacity: afterglowResting, scale: 1.0, duration: 0.5, easesOut: true),
    ]
}

/// The wordmark heart glyph, shared so a session's heart covers the home one exactly.
struct HeartGlyph: View {
    /// Settles the glyph onto the wordmark's baseline; applied outside the anchored frame.
    static let baselineOffset: CGFloat = 1

    var body: some View {
        Text("♥")
            .font(.system(size: 8))
    }
}

extension View {
    /// Centers the view on the heart's resting spot, in the coordinate space `frame` was resolved in.
    func placedOnHeart(_ frame: CGRect) -> some View {
        position(x: frame.midX, y: frame.midY + HeartGlyph.baselineOffset)
    }
}
