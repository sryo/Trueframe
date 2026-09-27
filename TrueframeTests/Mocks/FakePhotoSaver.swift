// Saver that records batches instead of touching the photo library.

import Foundation
@testable import Trueframe

actor FakePhotoSaver: PhotoSaving {
    private(set) var savedBatches: [[LibrarySaver.Item]] = []

    private var holdsSaves = false
    private var saveGate: CheckedContinuation<Void, Never>?

    func save(_ items: [LibrarySaver.Item]) async -> Int {
        savedBatches.append(items)
        if holdsSaves {
            await withCheckedContinuation { saveGate = $0 }
        }
        return items.count
    }

    /// Makes save() suspend, like a photo library write that never answers, until releaseSaves().
    func holdSaves() {
        holdsSaves = true
    }

    func releaseSaves() {
        holdsSaves = false
        saveGate?.resume()
        saveGate = nil
    }
}
