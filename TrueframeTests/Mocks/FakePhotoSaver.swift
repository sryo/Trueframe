// Saver that records batches instead of touching the photo library.

import Foundation
@testable import Trueframe

actor FakePhotoSaver: PhotoSaving {
    private(set) var savedBatches: [[LibrarySaver.Item]] = []

    func save(_ items: [LibrarySaver.Item]) async -> Int {
        savedBatches.append(items)
        return items.count
    }
}
