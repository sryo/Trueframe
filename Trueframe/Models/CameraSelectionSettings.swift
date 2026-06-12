// Camera lens selection settings.

import Foundation
import Observation

enum BackCameraType: String, CaseIterable, Equatable, Sendable {
    case wide
    case ultrawide
    case telephoto
}

@MainActor
@Observable
final class CameraSelectionSettings {
    private enum Keys {
        static let selectedCamera = "camera.selected"
        static let flash = "camera.flash"
    }

    var selectedCamera: BackCameraType {
        didSet { UserDefaults.standard.set(selectedCamera.rawValue, forKey: Keys.selectedCamera) }
    }

    var flashEnabled: Bool {
        didSet { UserDefaults.standard.set(flashEnabled, forKey: Keys.flash) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Default: wide camera selected, flash off
        if let rawValue = defaults.string(forKey: Keys.selectedCamera),
           let camera = BackCameraType(rawValue: rawValue) {
            self.selectedCamera = camera
        } else {
            self.selectedCamera = .wide
        }
        self.flashEnabled = defaults.object(forKey: Keys.flash) as? Bool ?? false
    }

    /// Select a camera (mutually exclusive - only one active at a time)
    func select(_ camera: BackCameraType) {
        selectedCamera = camera
    }
}
