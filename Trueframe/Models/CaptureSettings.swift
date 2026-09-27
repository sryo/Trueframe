// Capture behavior settings.

import Foundation
import Observation

@MainActor
@Observable
final class CaptureSettings {
    private enum Keys {
        static let captureInterval = "capture.interval"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private var storedInterval: Double

    /// Always one of `intervalOptions`; other values snap to the nearest one.
    var captureInterval: Double {
        get { storedInterval }
        set {
            storedInterval = Self.sanitizedInterval(newValue)
            defaults.set(storedInterval, forKey: Keys.captureInterval)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Keys.captureInterval) as? Double
        self.storedInterval = Self.sanitizedInterval(stored ?? Self.defaultInterval)
    }

    static let intervalOptions: [Double] = [0.25, 0.5, 1.0, 2.0, 5.0]
    static let defaultInterval = 1.0

    static func sanitizedInterval(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultInterval }
        return intervalOptions.min { abs($0 - value) < abs($1 - value) } ?? defaultInterval
    }

    static func formatInterval(_ interval: Double) -> String {
        if interval < 1.0 {
            return String(format: "%.2gs", interval)
        } else {
            return "\(Int(interval))s"
        }
    }
}
