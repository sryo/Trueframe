// Capture behavior settings for Trueframe.

import Foundation
import Observation

/// Settings that control capture behavior
@Observable
final class CaptureSettings {
    private enum Keys {
        static let livePhotosEnabled = "capture.livePhotos"
        static let smartSelectionEnabled = "capture.smartSelection"
        static let autoSaveBest = "capture.autoSaveBest"
        static let captureInterval = "capture.interval"
    }

    /// Whether to automatically create Live Photos from capture sessions
    var livePhotosEnabled: Bool {
        didSet { UserDefaults.standard.set(livePhotosEnabled, forKey: Keys.livePhotosEnabled) }
    }

    /// Whether to use Vision to auto-select best photos
    var smartSelectionEnabled: Bool {
        didSet { UserDefaults.standard.set(smartSelectionEnabled, forKey: Keys.smartSelectionEnabled) }
    }

    /// Whether to automatically save only the best photos
    var autoSaveBest: Bool {
        didSet { UserDefaults.standard.set(autoSaveBest, forKey: Keys.autoSaveBest) }
    }

    /// Capture interval in seconds (for photo mode)
    var captureInterval: Double {
        didSet { UserDefaults.standard.set(captureInterval, forKey: Keys.captureInterval) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.livePhotosEnabled = defaults.object(forKey: Keys.livePhotosEnabled) as? Bool ?? false
        self.smartSelectionEnabled = defaults.object(forKey: Keys.smartSelectionEnabled) as? Bool ?? true
        self.autoSaveBest = defaults.object(forKey: Keys.autoSaveBest) as? Bool ?? true
        self.captureInterval = defaults.object(forKey: Keys.captureInterval) as? Double ?? 1.0
    }

    /// Available capture intervals (0.25 = burst-like speed)
    static let intervalOptions: [Double] = [0.25, 0.5, 1.0, 2.0, 5.0]

    /// Format interval for display
    static func formatInterval(_ interval: Double) -> String {
        if interval < 1.0 {
            return String(format: "%.2gs", interval)
        } else {
            return "\(Int(interval))s"
        }
    }
}
