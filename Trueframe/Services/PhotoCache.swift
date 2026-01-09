// Disk-backed photo cache with memory-efficient thumbnail support.
// Prevents memory crashes by offloading full-resolution images to disk.

import UIKit

/// Thread-safe photo cache that stores full images on disk and thumbnails in memory.
actor PhotoCache {
    static let shared = PhotoCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let thumbnailSize = CGSize(width: 220, height: 220) // 2x for 110pt display

    /// In-memory thumbnail cache (small footprint: ~50KB per thumbnail)
    private var thumbnailCache: [UUID: UIImage] = [:]

    /// Tracks photo order for session
    private var photoOrder: [UUID] = []

    /// Session identifier for grouping photos
    private var currentSessionID: UUID?

    private init() {
        // Safe fallback to temp directory if caches unavailable
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("PhotoCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Session Management

    /// Start a new capture session
    func startSession() -> UUID {
        let sessionID = UUID()
        currentSessionID = sessionID
        photoOrder = []
        thumbnailCache = [:]
        return sessionID
    }

    /// End current session and return photo IDs in order
    func endSession() -> [UUID] {
        let order = photoOrder
        photoOrder = []
        currentSessionID = nil
        return order
    }

    // MARK: - Photo Storage

    /// Store a photo to disk and cache its thumbnail
    /// - Returns: The photo ID for later retrieval
    func store(_ image: UIImage, id: UUID = UUID()) async -> UUID {
        photoOrder.append(id)

        // Generate thumbnail for memory cache
        let thumbnail = await generateThumbnail(from: image)
        thumbnailCache[id] = thumbnail

        // Write full image to disk asynchronously
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.writeToDisk(image: image, id: id)
        }

        return id
    }

    /// Write full-resolution image to disk
    private func writeToDisk(image: UIImage, id: UUID) {
        let url = fileURL(for: id)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Photo Retrieval

    /// Get thumbnail from memory cache (fast, for UI display)
    func thumbnail(for id: UUID) -> UIImage? {
        thumbnailCache[id]
    }

    /// Get all thumbnails in session order
    func allThumbnails() -> [UIImage] {
        photoOrder.compactMap { thumbnailCache[$0] }
    }

    /// Load full-resolution image from disk
    func fullImage(for id: UUID) async -> UIImage? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Get photo count for current session
    var photoCount: Int {
        photoOrder.count
    }

    // MARK: - Cleanup

    /// Clear current session cache (call after photos saved to Camera Roll)
    func clearSession() {
        for id in photoOrder {
            let url = fileURL(for: id)
            try? fileManager.removeItem(at: url)
        }
        thumbnailCache = [:]
        photoOrder = []
        currentSessionID = nil
    }

    /// Clear all cached photos (emergency cleanup)
    func clearAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        thumbnailCache = [:]
        photoOrder = []
    }

    // MARK: - Memory Pressure Handling

    /// Called when system is under memory pressure
    func handleMemoryWarning() {
        // Keep only first 5 thumbnails for UI
        let keepCount = 5
        if photoOrder.count > keepCount {
            let idsToRemove = Array(photoOrder.dropFirst(keepCount))
            for id in idsToRemove {
                thumbnailCache.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Private Helpers

    private func fileURL(for id: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func generateThumbnail(from image: UIImage) async -> UIImage {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [thumbnailSize] in
                let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
                let thumbnail = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                }
                continuation.resume(returning: thumbnail)
            }
        }
    }
}
