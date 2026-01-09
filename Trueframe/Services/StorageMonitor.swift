// Checks available storage during capture.

import Foundation

final class StorageMonitor {
    private var timer: Timer?

    var hasAdequateSpace: Bool { FileManager.default.hasAdequateSpace }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stopMonitoring() }
}
