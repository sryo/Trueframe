// Layout math for the interval scrub wheel: a fixed window whose center holds the value.
// Offsets are the row's leading edge in window coordinates.

import CoreGraphics
import Foundation

enum ScrubWheelMath {
    static let windowWidth: CGFloat = 120
    static let itemWidth: CGFloat = 32
    static let spacing: CGFloat = 4
    /// Distance between neighboring item centers, which is what a drag travels per step.
    static let pitch: CGFloat = itemWidth + spacing

    static func nearestIndex(for interval: Double) -> Int {
        let options = CaptureSettings.intervalOptions
        return options.firstIndex(of: CaptureSettings.sanitizedInterval(interval)) ?? 0
    }

    static func rowOffset(for index: Int) -> CGFloat {
        windowWidth / 2 - itemWidth / 2 - CGFloat(index) * pitch
    }

    /// Dragging left (a smaller offset) moves toward longer intervals.
    static func nearestIndex(forRowOffset offset: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let position = ((rowOffset(for: 0) - offset) / pitch).rounded()
        return min(max(Int(position), 0), count - 1)
    }

    static func tappedIndex(atX x: CGFloat, rowOffset offset: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let position = ((x - offset - itemWidth / 2) / pitch).rounded()
        return min(max(Int(position), 0), count - 1)
    }

    /// How many steps an item sits from the center; fractional mid-drag.
    static func distance(of index: Int, rowOffset offset: CGFloat) -> Double {
        let centered = (rowOffset(for: 0) - offset) / pitch
        return abs(Double(index) - Double(centered))
    }

    static func opacity(atDistance distance: Double) -> Double {
        max(0.15, 1 - 0.35 * distance)
    }

    static func scale(atDistance distance: Double) -> Double {
        1 - 0.08 * min(distance, 2)
    }

    static func isCentered(atDistance distance: Double) -> Bool {
        distance < 0.5
    }

    static func steppedIndex(from index: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + step, 0), count - 1)
    }

    static func accessibilityValue(for interval: Double) -> String {
        let number = String(format: "%g", interval)
        return interval == 1 ? "\(number) second" : "\(number) seconds"
    }
}
