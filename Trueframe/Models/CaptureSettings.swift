// Capture behavior settings.

import Foundation
import Observation

@Observable
final class CaptureSettings {
    private enum Keys {
        static let livePhotosEnabled = "capture.livePhotos"
        static let smartSelectionEnabled = "capture.smartSelection"
        static let autoSaveBest = "capture.autoSaveBest"
        static let captureInterval = "capture.interval"
    }

    var livePhotosEnabled: Bool {
        didSet { UserDefaults.standard.set(livePhotosEnabled, forKey: Keys.livePhotosEnabled) }
    }

    var smartSelectionEnabled: Bool {
        didSet { UserDefaults.standard.set(smartSelectionEnabled, forKey: Keys.smartSelectionEnabled) }
    }

    var autoSaveBest: Bool {
        didSet { UserDefaults.standard.set(autoSaveBest, forKey: Keys.autoSaveBest) }
    }

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

    static let intervalOptions: [Double] = [0.25, 0.5, 1.0, 2.0, 5.0]

    static func formatInterval(_ interval: Double) -> String {
        if interval < 1.0 {
            return String(format: "%.2gs", interval)
        } else {
            return "\(Int(interval))s"
        }
    }
}
