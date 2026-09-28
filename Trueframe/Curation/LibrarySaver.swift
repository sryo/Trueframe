import os
import Photos

protocol PhotoSaving: Sendable {
    func save(_ items: [LibrarySaver.Item]) async -> Int
}

struct LibrarySaver: PhotoSaving {
    private static let logger = Logger(subsystem: "com.sryo.trueframe", category: "LibrarySaver")

    struct Item: Sendable {
        let data: Data
        let isProxy: Bool
        let capturedAt: Date
    }

    private let authorizationStatus: @Sendable () -> PHAuthorizationStatus

    init(authorizationStatus: @escaping @Sendable () -> PHAuthorizationStatus = {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }) {
        self.authorizationStatus = authorizationStatus
    }

    /// Saves all items in a single photo-library transaction, returning how
    /// many succeeded. Proxy items are added as deferred photo proxies; Photos
    /// finishes full-quality processing in the background after this app is done.
    func save(_ items: [Item]) async -> Int {
        guard !items.isEmpty else { return 0 }
        // Without access, performChanges waits on a prompt nobody may answer
        let status = authorizationStatus()
        guard status == .authorized || status == .limited else { return 0 }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for item in items {
                    Self.addCreationRequest(for: item)
                }
            }
            return items.count
        } catch {
            // The batch is all-or-nothing; salvage what we can one at a time
            Self.logger.error("Batch save failed, retrying individually: \(error, privacy: .public)")
            var saved = 0
            for item in items {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        Self.addCreationRequest(for: item)
                    }
                    saved += 1
                } catch {
                    Self.logger.error("Saving a photo failed: \(error, privacy: .public)")
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
