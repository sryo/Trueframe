// Shared UserDefaults cleanup for settings-related tests.

import Foundation

enum TestDefaults {
    static let settingsKeys = ["capture.interval", "camera.selected", "camera.flash"]

    static func clear() {
        for key in settingsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
