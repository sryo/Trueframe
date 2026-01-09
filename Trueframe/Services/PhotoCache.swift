// Stores photos on disk with in-memory thumbnails.

import UIKit

actor PhotoCache {
    static let shared = PhotoCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let thumbnailSize = CGSize(width: 220, height: 220)
    private var thumbnailCache: [UUID: UIImage] = [:]
    private var photoOrder: [UUID] = []

    private init() {
        // Safe fallback to temp directory if caches unavailable
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("PhotoCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Session Management

    func startSession() -> UUID {
        let sessionID = UUID()
        photoOrder = []
        thumbnailCache = [:]
        return sessionID
    }

    func endSession() -> [UUID] {
        let order = photoOrder
        photoOrder = []
        return order
    }

    // MARK: - Photo Storage

    func store(_ image: UIImage, id: UUID = UUID()) async -> UUID {
        photoOrder.append(id)

        let thumbnail = await generateThumbnail(from: image)
        thumbnailCache[id] = thumbnail

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.writeToDisk(image: image, id: id)
        }

        return id
    }

    private func writeToDisk(image: UIImage, id: UUID) {
        let url = fileURL(for: id)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Photo Retrieval

    func thumbnail(for id: UUID) -> UIImage? {
        thumbnailCache[id]
    }

    func allThumbnails() -> [UIImage] {
        photoOrder.compactMap { thumbnailCache[$0] }
    }

    func fullImage(for id: UUID) async -> UIImage? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    var photoCount: Int {
        photoOrder.count
    }

    func getPhotoIDs() -> [UUID] {
        photoOrder
    }

    // MARK: - Cleanup

    func clearSession() {
        for id in photoOrder {
            let url = fileURL(for: id)
            try? fileManager.removeItem(at: url)
        }
        thumbnailCache = [:]
        photoOrder = []
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        thumbnailCache = [:]
        photoOrder = []
    }

    // MARK: - Memory Pressure

    func handleMemoryWarning() {
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
