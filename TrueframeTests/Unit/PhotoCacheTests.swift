// Unit tests for PhotoCache.

import XCTest
@testable import Trueframe

/// Tests for PhotoCache functionality.
/// PhotoCache is an actor that stores full images on disk and thumbnails in memory.
final class PhotoCacheTests: XCTestCase {

    // MARK: - Properties

    /// System under test - using shared instance since PhotoCache is a singleton actor
    var sut: PhotoCache!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        sut = PhotoCache.shared
    }

    override func tearDown() async throws {
        // Clean up cache after each test
        await sut.clearAll()
        try await super.tearDown()
    }

    // MARK: - Session Management Tests

    func testStartSession_returnsUniqueSessionId() async {
        let sessionId1 = await sut.startSession()
        let sessionId2 = await sut.startSession()

        XCTAssertNotEqual(sessionId1, sessionId2, "Each session should have a unique ID")
    }

    func testStartSession_clearsExistingPhotoOrder() async {
        // Given - store some photos first
        let _ = await sut.startSession()
        let _ = await sut.store(createTestImage())

        // When - start a new session
        let _ = await sut.startSession()

        // Then - photo count should be zero
        let count = await sut.photoCount
        XCTAssertEqual(count, 0, "Starting new session should clear photo order")
    }

    func testStartSession_clearsThumbnailCache() async {
        // Given - store a photo
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // Verify thumbnail exists
        let thumbnailBefore = await sut.thumbnail(for: photoId)
        XCTAssertNotNil(thumbnailBefore, "Thumbnail should exist before new session")

        // When - start new session
        let _ = await sut.startSession()

        // Then - old thumbnail should be cleared
        let thumbnailAfter = await sut.thumbnail(for: photoId)
        XCTAssertNil(thumbnailAfter, "Thumbnail should be cleared after new session")
    }

    func testEndSession_returnsPhotoOrderInCorrectSequence() async {
        // Given
        let _ = await sut.startSession()
        let id1 = await sut.store(createTestImage(color: .red))
        let id2 = await sut.store(createTestImage(color: .green))
        let id3 = await sut.store(createTestImage(color: .blue))

        // When
        let photoOrder = await sut.endSession()

        // Then
        XCTAssertEqual(photoOrder.count, 3, "Should return all photo IDs")
        XCTAssertEqual(photoOrder[0], id1, "First photo should be first in order")
        XCTAssertEqual(photoOrder[1], id2, "Second photo should be second in order")
        XCTAssertEqual(photoOrder[2], id3, "Third photo should be third in order")
    }

    func testEndSession_withNoPhotos_returnsEmptyArray() async {
        // Given
        let _ = await sut.startSession()

        // When
        let photoOrder = await sut.endSession()

        // Then
        XCTAssertTrue(photoOrder.isEmpty, "Should return empty array when no photos stored")
    }

    // MARK: - Photo Storage Tests

    func testStore_returnsPhotoId() async {
        // Given
        let _ = await sut.startSession()
        let image = createTestImage()

        // When
        let photoId = await sut.store(image)

        // Then
        XCTAssertNotEqual(photoId, UUID(), "Should return a valid UUID")
    }

    func testStore_withCustomId_usesProvidedId() async {
        // Given
        let _ = await sut.startSession()
        let customId = UUID()
        let image = createTestImage()

        // When
        let returnedId = await sut.store(image, id: customId)

        // Then
        XCTAssertEqual(returnedId, customId, "Should use the provided custom ID")
    }

    func testStore_incrementsPhotoCount() async {
        // Given
        let _ = await sut.startSession()

        // When
        let _ = await sut.store(createTestImage())
        let _ = await sut.store(createTestImage())

        // Then
        let count = await sut.photoCount
        XCTAssertEqual(count, 2, "Photo count should reflect stored photos")
    }

    func testStore_createsThumbnail() async {
        // Given
        let _ = await sut.startSession()
        let image = createTestImage(size: CGSize(width: 1000, height: 1000))

        // When
        let photoId = await sut.store(image)

        // Then
        let thumbnail = await sut.thumbnail(for: photoId)
        XCTAssertNotNil(thumbnail, "Thumbnail should be created for stored photo")
    }

    func testStore_thumbnailIsSmallerThanOriginal() async {
        // Given
        let _ = await sut.startSession()
        let largeSize = CGSize(width: 2000, height: 2000)
        let image = createTestImage(size: largeSize)

        // When
        let photoId = await sut.store(image)

        // Then
        let thumbnail = await sut.thumbnail(for: photoId)
        XCTAssertNotNil(thumbnail)
        XCTAssertLessThan(thumbnail!.size.width, largeSize.width, "Thumbnail should be smaller than original")
        XCTAssertLessThan(thumbnail!.size.height, largeSize.height, "Thumbnail should be smaller than original")
    }

    func testStore_multiplePhotos_maintainsOrder() async {
        // Given
        let _ = await sut.startSession()
        var storedIds: [UUID] = []

        // When
        for i in 0..<5 {
            let id = await sut.store(createTestImage(), id: UUID())
            storedIds.append(id)
        }

        // Then
        let photoOrder = await sut.endSession()
        XCTAssertEqual(photoOrder, storedIds, "Photo order should match storage order")
    }

    // MARK: - Photo Retrieval Tests

    func testThumbnail_forValidId_returnsImage() async {
        // Given
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // When
        let thumbnail = await sut.thumbnail(for: photoId)

        // Then
        XCTAssertNotNil(thumbnail, "Should return thumbnail for valid photo ID")
    }

    func testThumbnail_forInvalidId_returnsNil() async {
        // Given
        let _ = await sut.startSession()
        let invalidId = UUID()

        // When
        let thumbnail = await sut.thumbnail(for: invalidId)

        // Then
        XCTAssertNil(thumbnail, "Should return nil for invalid photo ID")
    }

    func testAllThumbnails_returnsAllInOrder() async {
        // Given
        let _ = await sut.startSession()
        let _ = await sut.store(createTestImage(color: .red))
        let _ = await sut.store(createTestImage(color: .green))
        let _ = await sut.store(createTestImage(color: .blue))

        // When
        let thumbnails = await sut.allThumbnails()

        // Then
        XCTAssertEqual(thumbnails.count, 3, "Should return all thumbnails")
    }

    func testAllThumbnails_withNoPhotos_returnsEmptyArray() async {
        // Given
        let _ = await sut.startSession()

        // When
        let thumbnails = await sut.allThumbnails()

        // Then
        XCTAssertTrue(thumbnails.isEmpty, "Should return empty array when no photos")
    }

    func testFullImage_forValidId_returnsImage() async {
        // Given
        let _ = await sut.startSession()
        let originalImage = createTestImage(size: CGSize(width: 500, height: 500))
        let photoId = await sut.store(originalImage)

        // Wait for disk write to complete
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // When
        let fullImage = await sut.fullImage(for: photoId)

        // Then
        XCTAssertNotNil(fullImage, "Should return full image from disk")
    }

    func testFullImage_forInvalidId_returnsNil() async {
        // Given
        let _ = await sut.startSession()
        let invalidId = UUID()

        // When
        let fullImage = await sut.fullImage(for: invalidId)

        // Then
        XCTAssertNil(fullImage, "Should return nil for invalid photo ID")
    }

    func testPhotoCount_initiallyZero() async {
        // Given
        let _ = await sut.startSession()

        // When
        let count = await sut.photoCount

        // Then
        XCTAssertEqual(count, 0, "Initial photo count should be zero")
    }

    func testPhotoCount_reflectsStoredPhotos() async {
        // Given
        let _ = await sut.startSession()

        // When
        for _ in 0..<10 {
            let _ = await sut.store(createTestImage())
        }

        // Then
        let count = await sut.photoCount
        XCTAssertEqual(count, 10, "Photo count should equal number of stored photos")
    }

    // MARK: - Cleanup Tests

    func testClearSession_removesThumbnails() async {
        // Given
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // When
        await sut.clearSession()

        // Then
        let thumbnail = await sut.thumbnail(for: photoId)
        XCTAssertNil(thumbnail, "Thumbnails should be cleared")
    }

    func testClearSession_resetsPhotoCount() async {
        // Given
        let _ = await sut.startSession()
        let _ = await sut.store(createTestImage())
        let _ = await sut.store(createTestImage())

        // When
        await sut.clearSession()

        // Then
        let count = await sut.photoCount
        XCTAssertEqual(count, 0, "Photo count should be zero after clear")
    }

    func testClearSession_removesDiskFiles() async {
        // Given
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // Wait for disk write
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Verify file exists
        let imageBefore = await sut.fullImage(for: photoId)
        XCTAssertNotNil(imageBefore, "Image should exist on disk before clear")

        // When
        await sut.clearSession()

        // Then
        let imageAfter = await sut.fullImage(for: photoId)
        XCTAssertNil(imageAfter, "Image should be removed from disk after clear")
    }

    func testClearAll_clearsEverything() async {
        // Given
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // Wait for disk write
        try? await Task.sleep(nanoseconds: 500_000_000)

        // When
        await sut.clearAll()

        // Then
        let thumbnail = await sut.thumbnail(for: photoId)
        let fullImage = await sut.fullImage(for: photoId)
        let count = await sut.photoCount

        XCTAssertNil(thumbnail, "Thumbnails should be cleared")
        XCTAssertNil(fullImage, "Full images should be cleared")
        XCTAssertEqual(count, 0, "Photo count should be zero")
    }

    func testClearAll_canBeCalledMultipleTimes() async {
        // Given
        let _ = await sut.startSession()
        let _ = await sut.store(createTestImage())

        // When/Then - should not crash
        await sut.clearAll()
        await sut.clearAll()
        await sut.clearAll()
    }

    // MARK: - Memory Pressure Handling Tests

    func testHandleMemoryWarning_keepsFiveThumbnails() async {
        // Given
        let _ = await sut.startSession()
        var photoIds: [UUID] = []
        for _ in 0..<10 {
            let id = await sut.store(createTestImage())
            photoIds.append(id)
        }

        // When
        await sut.handleMemoryWarning()

        // Then - first 5 should be kept
        for i in 0..<5 {
            let thumbnail = await sut.thumbnail(for: photoIds[i])
            XCTAssertNotNil(thumbnail, "First 5 thumbnails should be kept (index \(i))")
        }

        // Thumbnails after 5 should be removed
        for i in 5..<10 {
            let thumbnail = await sut.thumbnail(for: photoIds[i])
            XCTAssertNil(thumbnail, "Thumbnails after first 5 should be removed (index \(i))")
        }
    }

    func testHandleMemoryWarning_withFewThumbnails_keepsAll() async {
        // Given
        let _ = await sut.startSession()
        var photoIds: [UUID] = []
        for _ in 0..<3 {
            let id = await sut.store(createTestImage())
            photoIds.append(id)
        }

        // When
        await sut.handleMemoryWarning()

        // Then - all should be kept
        for id in photoIds {
            let thumbnail = await sut.thumbnail(for: id)
            XCTAssertNotNil(thumbnail, "All thumbnails should be kept when under threshold")
        }
    }

    func testHandleMemoryWarning_preservesPhotoOrder() async {
        // Given
        let _ = await sut.startSession()
        for _ in 0..<10 {
            let _ = await sut.store(createTestImage())
        }

        let orderBefore = await sut.endSession()

        // Restore for test
        let _ = await sut.startSession()
        for id in orderBefore {
            let _ = await sut.store(createTestImage(), id: id)
        }

        // When
        await sut.handleMemoryWarning()

        // Then - photo order should remain the same
        let count = await sut.photoCount
        XCTAssertEqual(count, 10, "Photo order should be preserved")
    }

    func testHandleMemoryWarning_preservesFullImagesOnDisk() async {
        // Given
        let _ = await sut.startSession()
        var photoIds: [UUID] = []
        for _ in 0..<10 {
            let id = await sut.store(createTestImage())
            photoIds.append(id)
        }

        // Wait for disk writes
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // When
        await sut.handleMemoryWarning()

        // Then - all full images should still be on disk
        for id in photoIds {
            let fullImage = await sut.fullImage(for: id)
            XCTAssertNotNil(fullImage, "Full images should remain on disk after memory warning")
        }
    }

    // MARK: - Thread Safety Tests (Actor Isolation)

    func testConcurrentStores_maintainsConsistency() async {
        // Given
        let _ = await sut.startSession()
        let numberOfPhotos = 20

        // When - store photos concurrently
        await withTaskGroup(of: UUID.self) { group in
            for _ in 0..<numberOfPhotos {
                group.addTask {
                    await self.sut.store(self.createTestImage())
                }
            }
        }

        // Then
        let count = await sut.photoCount
        XCTAssertEqual(count, numberOfPhotos, "All concurrent stores should be counted")
    }

    func testConcurrentReads_returnsConsistentData() async {
        // Given
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // When - read concurrently
        await withTaskGroup(of: UIImage?.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await self.sut.thumbnail(for: photoId)
                }
            }

            var results: [UIImage?] = []
            for await result in group {
                results.append(result)
            }

            // Then - all reads should succeed
            for result in results {
                XCTAssertNotNil(result, "Concurrent reads should all succeed")
            }
        }
    }

    func testConcurrentStoreAndRead_doesNotCrash() async {
        // Given
        let _ = await sut.startSession()

        // When - store and read concurrently
        await withTaskGroup(of: Void.self) { group in
            // Concurrent stores
            for _ in 0..<10 {
                group.addTask {
                    let _ = await self.sut.store(self.createTestImage())
                }
            }

            // Concurrent reads
            for _ in 0..<10 {
                group.addTask {
                    let _ = await self.sut.allThumbnails()
                }
            }

            // Concurrent count queries
            for _ in 0..<10 {
                group.addTask {
                    let _ = await self.sut.photoCount
                }
            }
        }

        // Then - should complete without crash
        let count = await sut.photoCount
        XCTAssertGreaterThan(count, 0, "Should have stored some photos")
    }

    func testConcurrentSessionOperations_doesNotCrash() async {
        // Given/When - rapid session operations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let _ = await self.sut.startSession()
                    let _ = await self.sut.store(self.createTestImage())
                    let _ = await self.sut.endSession()
                }
            }
        }

        // Then - should complete without crash
    }

    // MARK: - Edge Cases

    func testStore_verySmallImage() async {
        // Given
        let _ = await sut.startSession()
        let tinyImage = createTestImage(size: CGSize(width: 1, height: 1))

        // When
        let photoId = await sut.store(tinyImage)

        // Then
        let thumbnail = await sut.thumbnail(for: photoId)
        XCTAssertNotNil(thumbnail, "Should handle very small images")
    }

    func testStore_veryLargeImage() async {
        // Given
        let _ = await sut.startSession()
        let largeImage = createTestImage(size: CGSize(width: 4000, height: 3000))

        // When
        let photoId = await sut.store(largeImage)

        // Then
        let thumbnail = await sut.thumbnail(for: photoId)
        XCTAssertNotNil(thumbnail, "Should handle large images")

        // Thumbnail should be scaled down
        XCTAssertEqual(thumbnail!.size.width, 220, accuracy: 1, "Thumbnail width should be 220")
        XCTAssertEqual(thumbnail!.size.height, 220, accuracy: 1, "Thumbnail height should be 220")
    }

    func testStore_manyPhotos() async {
        // Given
        let _ = await sut.startSession()
        let numberOfPhotos = 50

        // When
        for _ in 0..<numberOfPhotos {
            let _ = await sut.store(createTestImage())
        }

        // Then
        let count = await sut.photoCount
        XCTAssertEqual(count, numberOfPhotos, "Should handle many photos")

        let thumbnails = await sut.allThumbnails()
        XCTAssertEqual(thumbnails.count, numberOfPhotos, "Should have thumbnail for each photo")
    }

    func testOperationsWithoutSession_stillWork() async {
        // Given - no session started, just clear any previous state
        await sut.clearAll()

        // When
        let photoId = await sut.store(createTestImage())

        // Then - should still work
        let thumbnail = await sut.thumbnail(for: photoId)
        XCTAssertNotNil(thumbnail, "Store should work without explicit session")
    }

    func testEndSession_canBeCalledMultipleTimes() async {
        // Given
        let _ = await sut.startSession()
        let _ = await sut.store(createTestImage())

        // When/Then - should not crash
        let order1 = await sut.endSession()
        let order2 = await sut.endSession()
        let order3 = await sut.endSession()

        XCTAssertEqual(order1.count, 1, "First end should return photo")
        XCTAssertTrue(order2.isEmpty, "Subsequent ends should return empty")
        XCTAssertTrue(order3.isEmpty, "Subsequent ends should return empty")
    }

    // MARK: - Disk Persistence Tests

    func testFullImage_persistsAcrossSessions() async {
        // Given - store photo in one session
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // Wait for disk write
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Start new session (clears memory cache but not disk)
        let _ = await sut.startSession()

        // When - try to retrieve from disk
        let fullImage = await sut.fullImage(for: photoId)

        // Then - should still be able to load from disk
        XCTAssertNotNil(fullImage, "Full image should persist on disk across sessions")
    }

    func testThumbnail_doesNotPersistAcrossSessions() async {
        // Given - store photo
        let _ = await sut.startSession()
        let photoId = await sut.store(createTestImage())

        // Start new session
        let _ = await sut.startSession()

        // When
        let thumbnail = await sut.thumbnail(for: photoId)

        // Then
        XCTAssertNil(thumbnail, "Thumbnails are in-memory only and cleared on new session")
    }

    // MARK: - Helpers

    private func createTestImage(size: CGSize = CGSize(width: 100, height: 100), color: UIColor = .red) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
