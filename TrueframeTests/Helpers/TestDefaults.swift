import Foundation

enum TestDefaults {
    private static let settingsKeys = ["capture.interval", "camera.selected", "camera.flash"]

    static func clear() {
        for key in settingsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
