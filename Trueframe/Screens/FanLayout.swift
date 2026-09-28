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

    static func photos(from previews: [UIImage]) -> [UIImage] {
        Array(previews.prefix(maxPhotos))
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
