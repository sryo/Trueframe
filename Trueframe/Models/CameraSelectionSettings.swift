// Camera selection settings for back camera lens types.

import Foundation
import Observation

enum BackCameraType: String, CaseIterable, Equatable, Sendable {
    case wide       // Main camera (1x)
    case ultrawide  // Ultrawide camera (0.5x)
    case telephoto  // Telephoto camera (2x/3x)
}

@Observable
final class CameraSelectionSettings {
    private enum Keys {
        static let selectedCamera = "camera.selected"
        static let flash = "camera.flash"
    }

    /// The currently selected camera (mutually exclusive)
    var selectedCamera: BackCameraType {
        didSet { UserDefaults.standard.set(selectedCamera.rawValue, forKey: Keys.selectedCamera) }
    }

    var flashEnabled: Bool {
        didSet { UserDefaults.standard.set(flashEnabled, forKey: Keys.flash) }
    }

    // MARK: - Lens Smudge Detection State

    /// Tracks which lenses are currently detected as smudged
    var smudgedLenses: Set<BackCameraType> = []

    /// Check if a specific lens is smudged
    func isSmudged(_ camera: BackCameraType) -> Bool {
        smudgedLenses.contains(camera)
    }

    /// Update smudge status for a lens
    func setSmudged(_ camera: BackCameraType, isSmudged: Bool) {
        if isSmudged {
            smudgedLenses.insert(camera)
        } else {
            smudgedLenses.remove(camera)
        }
    }

    /// Clear all smudge states
    func clearSmudgeStates() {
        smudgedLenses.removeAll()
    }

    // Convenience properties for backwards compatibility
    var wideEnabled: Bool { selectedCamera == .wide }
    var ultrawideEnabled: Bool { selectedCamera == .ultrawide }
    var telephotoEnabled: Bool { selectedCamera == .telephoto }

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

    func isEnabled(_ camera: BackCameraType) -> Bool {
        selectedCamera == camera
    }

    /// Select a camera (mutually exclusive - only one active at a time)
    func select(_ camera: BackCameraType) {
        selectedCamera = camera
    }
}
