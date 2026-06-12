// Saves captured photos to the user's photo library.

import Photos

struct LibrarySaver: Sendable {
    struct Item: Sendable {
        let data: Data
        let isProxy: Bool
        let capturedAt: Date
    }

    /// Saves all items in a single photo-library transaction, returning how
    /// many succeeded. Proxy items are added as deferred photo proxies; Photos
    /// finishes full-quality processing in the background after this app is done.
    func save(_ items: [Item]) async -> Int {
        guard !items.isEmpty else { return 0 }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for item in items {
                    Self.addCreationRequest(for: item)
                }
            }
            return items.count
        } catch {
            // The batch is all-or-nothing; salvage what we can one at a time
            print("[LibrarySaver] Batch save failed, retrying individually: \(error)")
            var saved = 0
            for item in items {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        Self.addCreationRequest(for: item)
                    }
                    saved += 1
                } catch {
                    print("[LibrarySaver] Failed to save photo: \(error)")
                }
            }
            return saved
        }
    }

    private static func addCreationRequest(for item: Item) {
        let request = PHAssetCreationRequest.forAsset()
        let resourceType: PHAssetResourceType = item.isProxy ? .photoProxy : .photo
        request.addResource(with: resourceType, data: item.data, options: nil)
        request.creationDate = item.capturedAt
    }
}
