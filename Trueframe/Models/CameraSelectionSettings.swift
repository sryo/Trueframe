import Foundation
import Observation

enum BackCameraType: String, CaseIterable, Sendable {
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

    @ObservationIgnored private let defaults: UserDefaults

    var selectedCamera: BackCameraType {
        didSet { defaults.set(selectedCamera.rawValue, forKey: Keys.selectedCamera) }
    }

    var flashEnabled: Bool {
        didSet { defaults.set(flashEnabled, forKey: Keys.flash) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: Keys.selectedCamera),
           let camera = BackCameraType(rawValue: rawValue) {
            self.selectedCamera = camera
        } else {
            self.selectedCamera = .wide
        }
        self.flashEnabled = defaults.object(forKey: Keys.flash) as? Bool ?? false
    }

    func select(_ camera: BackCameraType) {
        selectedCamera = camera
    }
}
