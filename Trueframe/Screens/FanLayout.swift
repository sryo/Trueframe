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
    /// Each side of upright.
    static let spread = Angle.degrees(25)
    static let radius: CGFloat = 240
    /// The arc's pivot sits this far below the screen's center, so the fan bows upward.
    static let pivotDrop: CGFloat = 200

    /// Photos rise into the fan from here, slightly shrunk.
    static let entryOffset = CGSize(width: 0, height: 200)
    static let entryScale: CGFloat = 0.8

    static let stagger: TimeInterval = 0.03
    static let hold: Duration = .seconds(0.7)

    /// How long a session too big to fan whole waits to learn its keepers.
    static let fanVerdictGrace: Duration = .seconds(0.2)
    /// How long the collapse waits past the hold for curation to say what's dropped.
    static let verdictDeadline: Duration = .seconds(0.5)

    /// Which photos fan out, in capture order: kept ones first when there are
    /// too many, then drops, so some misses can still show.
    static func shownIndices(count: Int, kept: [Bool]?) -> [Int] {
        guard count > maxPhotos, let kept, kept.count == count else { return Array(0..<min(count, maxPhotos)) }
        let keepers = (0..<count).filter { kept[$0] }
        let drops = (0..<count).filter { !kept[$0] }
        return Array((keepers + drops).prefix(maxPhotos)).sorted()
    }

    /// Whether each shown photo reaches the heart. Without a verdict, or with
    /// none of the shown kept, they all do: the heart has to be fed to burst.
    static func keptFlags(shown: [Int], verdict: [Bool]?) -> [Bool] {
        let all = Array(repeating: true, count: shown.count)
        guard let verdict else { return all }
        let flags = shown.map { $0 < verdict.count ? verdict[$0] : true }
        return flags.contains(true) ? flags : all
    }

    /// The verdict once known, or nil if it isn't by the deadline.
    @MainActor
    static func awaitVerdict(within deadline: Duration, read: @MainActor () -> [Bool]?) async -> [Bool]? {
        let end = ContinuousClock.now + deadline
        while ContinuousClock.now < end, !Task.isCancelled {
            if let verdict = read() { return verdict }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return read()
    }

    static func slots(count: Int) -> [Slot] {
        let count = min(count, maxPhotos)
        return (0..<count).map { index in
            let fraction = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let angle = Angle.radians(spread.radians * (2 * fraction - 1))
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
