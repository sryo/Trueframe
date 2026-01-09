// Checks available storage during capture.

import Foundation

final class StorageMonitor {
    var hasAdequateSpace: Bool { FileManager.default.hasAdequateSpace }

    func startMonitoring() {}
    func stopMonitoring() {}
}
