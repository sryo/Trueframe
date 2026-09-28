// Holds one session's captures: compressed data on disk, previews in memory.

import UIKit

actor SessionStore {
    struct Entry: Sendable {
        let id: UUID
        let isProxy: Bool
        let capturedAt: Date
        let preview: UIImage?
    }

    private let directory: URL
    private var entries: [Entry] = []

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CaptureSession", isDirectory: true)
    }

    init(directory: URL = SessionStore.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes the photo container data to disk untouched (no re-encoding)
    /// and keeps the small preview in memory.
    func add(_ asset: CapturedAsset) {
        try? asset.fileData.write(to: fileURL(for: asset.id), options: .atomic)
        entries.append(Entry(
            id: asset.id,
            isProxy: asset.isProxy,
            capturedAt: asset.capturedAt,
            preview: asset.preview
        ))
    }

    var count: Int {
        entries.count
    }

    func allEntries() -> [Entry] {
        entries
    }

    func fileData(for id: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: id))
    }

    func clearSession() {
        for entry in entries {
            try? FileManager.default.removeItem(at: fileURL(for: entry.id))
        }
        entries = []
    }

    /// Hands the current entries' files to whoever still holds those entries,
    /// so clearing the next session cannot delete them.
    func detachSession() {
        entries = []
    }

    func removeFiles(for ids: [UUID]) {
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).photo")
    }
}
