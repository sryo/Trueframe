// When and how each part of the home screen arrives and leaves.

import Foundation

enum HomeReveal {
    enum Part: Hashable {
        case line(Int)
        case wordmark
        case controls

        static var all: [Part] { lines.indices.map(Part.line) + [.wordmark, .controls] }

        /// The controls only fade in; rising would pull them away from the corner they live in.
        var rises: Bool { self != .controls }
    }

    enum State {
        /// Below and blurred, ready to rise.
        case waiting
        case shown
        /// Just dissolved on the way out.
        case left
    }

    struct Pose: Equatable {
        var opacity: Double
        var offsetY: Double
        var blur: Double
    }

    static let lines = ["hold to your heart", "to capture life"]

    static let lineStagger: TimeInterval = 0.12
    static let riseDistance = 12.0
    static let sinkDistance = 4.0
    static let startBlur = 6.0

    static func delay(for part: Part, after start: TimeInterval) -> TimeInterval {
        switch part {
        case .line(let index): start + Double(index) * lineStagger
        case .wordmark: start + Double(lines.count) * lineStagger + 0.06
        case .controls: start + 0.5
        }
    }

    static func pose(for part: Part, state: State, reduceMotion: Bool) -> Pose {
        let pose = switch state {
        case .waiting: Pose(opacity: 0, offsetY: part.rises ? riseDistance : 0, blur: startBlur)
        case .shown: Pose(opacity: 1, offsetY: 0, blur: 0)
        case .left: Pose(opacity: 0, offsetY: sinkDistance, blur: 0)
        }
        return reduceMotion ? Pose(opacity: pose.opacity, offsetY: 0, blur: 0) : pose
    }
}
