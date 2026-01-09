// Storage space helpers.

import Foundation

extension FileManager {
    private static let minimumRequiredSpace: Int64 = 100 * 1024 * 1024

    var hasAdequateSpace: Bool {
        guard let homeURL = urls(for: .documentDirectory, in: .userDomainMask).first,
              let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return false
        }
        return available > Self.minimumRequiredSpace
    }
}
