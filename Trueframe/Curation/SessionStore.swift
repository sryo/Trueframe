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

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("CaptureSession", isDirectory: true)
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

    var previews: [UIImage] {
        entries.compactMap(\.preview)
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

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).photo")
    }
}
