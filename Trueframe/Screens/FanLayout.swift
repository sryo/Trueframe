import SwiftUI

/// Where the session's photos sit when they fan out, as offsets from the screen's center.
enum FanLayout {
    struct Slot: Equatable {
        let offset: CGSize
        let rotation: Angle
    }

    static let maxPhotos = 7
    static let photoSize: CGFloat = 96
    static let cornerRadius: CGFloat = 10
    /// Each side of upright, for a full fan.
    static let spread = Angle.degrees(25)
    static let radius: CGFloat = 240
    /// The arc's pivot sits this far below the screen's center, so the fan bows upward.
    static let pivotDrop: CGFloat = 200

    /// Photos rise into the fan from here, slightly shrunk.
    static let entryOffset = CGSize(width: 0, height: 200)
    static let entryScale: CGFloat = 0.8

    static let stagger: TimeInterval = 0.03
    static let hold: Duration = .seconds(0.7)

    enum Plan: Equatable {
        /// Nothing judged in time, or nothing to show: straight home.
        case skip
        /// Indices into the previews, in capture order.
        case fan([Int])
    }

    /// How long from the end of a session the fan waits to learn what's kept.
    /// Nothing is shown before then, since an unjudged photo might be dropped.
    static let verdictDeadline: Duration = .seconds(1.5)

    /// Only kept photos fan out, in capture order. Past the fan's size, the
    /// best scored win.
    static func plan(for verdict: Verdict?) -> Plan {
        guard let verdict else { return .skip }
        let keepers = verdict.kept.indices.filter { verdict.kept[$0] }
        guard !keepers.isEmpty else { return .skip }
        guard keepers.count > maxPhotos else { return .fan(keepers) }
        guard verdict.scores.count == verdict.kept.count else { return .fan(Array(keepers.prefix(maxPhotos))) }
        // Stable on ties, so earlier captures win them
        let best = keepers.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (verdict.scores[lhs.element], verdict.scores[rhs.element])
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .prefix(maxPhotos)
            .map(\.element)
        return .fan(best.sorted())
    }

    /// The verdict once known, or nil if it isn't by the deadline.
    @MainActor
    static func awaitVerdict(within deadline: Duration, read: @MainActor () -> Verdict?) async -> Verdict? {
        let end = ContinuousClock.now + deadline
        while ContinuousClock.now < end, !Task.isCancelled {
            if let verdict = read() { return verdict }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return read()
    }

    static func slots(count: Int) -> [Slot] {
        let count = min(count, maxPhotos)
        // A small session narrows, but less than proportionally, so a pair still reads as a fan
        let half = count > 1 ? spread.radians * (Double(count - 1) / Double(maxPhotos - 1)).squareRoot() : 0
        return (0..<count).map { index in
            let fraction = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let angle = Angle.radians(half * (2 * fraction - 1))
            return Slot(
                offset: CGSize(
                    width: sin(angle.radians) * radius,
                    height: -cos(angle.radians) * radius + pivotDrop
                ),
                rotation: angle
            )
        }
    }

    static func delay(for index: Int) -> TimeInterval {
        Double(index) * stagger
    }
}
