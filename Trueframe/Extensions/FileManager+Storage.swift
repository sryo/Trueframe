import Foundation

extension FileManager {
    static let minimumRequiredSpace: Int64 = 100 * 1024 * 1024

    var hasAdequateSpace: Bool {
        let documents = urls(for: .documentDirectory, in: .userDomainMask).first
        let values = try? documents?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Self.hasAdequateSpace(available: values?.volumeAvailableCapacityForImportantUsage)
    }

    /// An unanswerable capacity query shouldn't block capturing; a full disk
    /// still stops the session once the query succeeds.
    static func hasAdequateSpace(available: Int64?) -> Bool {
        guard let available else { return true }
        return available > minimumRequiredSpace
    }
}
