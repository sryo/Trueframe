// Index math for the capture interval picker.

import CoreGraphics

enum IntervalPickerGeometry {
    static let itemWidth: CGFloat = 32
    static let spacing: CGFloat = 4
    /// Distance between neighboring item centers, which is what a drag travels per step.
    static let pitch: CGFloat = itemWidth + spacing

    static func nearestIndex(for interval: Double) -> Int {
        let options = CaptureSettings.intervalOptions
        return options.firstIndex(of: CaptureSettings.sanitizedInterval(interval)) ?? 0
    }

    /// Dragging left (negative offset) moves toward longer intervals.
    static func previewIndex(current: Int, dragOffset: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        guard pitch > 0 else { return min(max(current, 0), count - 1) }
        let target = current + Int((-dragOffset / pitch).rounded())
        return min(max(target, 0), count - 1)
    }
}
