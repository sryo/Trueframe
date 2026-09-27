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

    var captureInterval: Double {
        didSet { defaults.set(captureInterval, forKey: Keys.captureInterval) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
