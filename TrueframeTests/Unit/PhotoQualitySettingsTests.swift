// Unit tests for PhotoQualitySettings.

import AVFoundation
import XCTest
@testable import Trueframe

/// Tests for PhotoQualitySettings and PhotoQualityMode functionality.
final class PhotoQualitySettingsTests: XCTestCase {

    var sut: PhotoQualitySettings!

    override func setUp() {
        super.setUp()
        clearUserDefaults()
        sut = PhotoQualitySettings()
    }

    override func tearDown() {
        sut = nil
        clearUserDefaults()
        super.tearDown()
    }

    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "photoQuality.mode")
    }

    // MARK: - PhotoQualityMode Tests

    func testPhotoQualityMode_allCases() {
        let allCases = PhotoQualityMode.allCases

        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.quality))
        XCTAssertTrue(allCases.contains(.balanced))
        XCTAssertTrue(allCases.contains(.fast))
    }

    func testPhotoQualityMode_rawValues() {
        XCTAssertEqual(PhotoQualityMode.quality.rawValue, "Quality")
        XCTAssertEqual(PhotoQualityMode.balanced.rawValue, "Balanced")
        XCTAssertEqual(PhotoQualityMode.fast.rawValue, "Fast")
    }

    func testPhotoQualityMode_initFromRawValue() {
        XCTAssertEqual(PhotoQualityMode(rawValue: "Quality"), .quality)
        XCTAssertEqual(PhotoQualityMode(rawValue: "Balanced"), .balanced)
        XCTAssertEqual(PhotoQualityMode(rawValue: "Fast"), .fast)
        XCTAssertNil(PhotoQualityMode(rawValue: "invalid"))
        XCTAssertNil(PhotoQualityMode(rawValue: "quality")) // case sensitive
    }

    func testPhotoQualityMode_identifiable() {
        XCTAssertEqual(PhotoQualityMode.quality.id, "Quality")
        XCTAssertEqual(PhotoQualityMode.balanced.id, "Balanced")
        XCTAssertEqual(PhotoQualityMode.fast.id, "Fast")
    }

    // MARK: - Subtitle Tests

    func testPhotoQualityMode_subtitles() {
        XCTAssertEqual(PhotoQualityMode.quality.subtitle, "Best photos, larger files")
        XCTAssertEqual(PhotoQualityMode.balanced.subtitle, "Great photos, reasonable storage")
        XCTAssertEqual(PhotoQualityMode.fast.subtitle, "Quick capture, smaller files")
    }

    // MARK: - Icon Name Tests

    func testPhotoQualityMode_iconNames() {
        XCTAssertEqual(PhotoQualityMode.quality.iconName, "sparkles")
        XCTAssertEqual(PhotoQualityMode.balanced.iconName, "scale.3d")
        XCTAssertEqual(PhotoQualityMode.fast.iconName, "bolt.fill")
    }

    // MARK: - Approximate File Size Tests

    func testPhotoQualityMode_approximateFileSizeMB() {
        XCTAssertEqual(PhotoQualityMode.quality.approximateFileSizeMB, 4.0)
        XCTAssertEqual(PhotoQualityMode.balanced.approximateFileSizeMB, 2.0)
        XCTAssertEqual(PhotoQualityMode.fast.approximateFileSizeMB, 1.0)
    }

    func testPhotoQualityMode_fileSizeDecreasesByMode() {
        // Quality should have the largest file size
        XCTAssertGreaterThan(
            PhotoQualityMode.quality.approximateFileSizeMB,
            PhotoQualityMode.balanced.approximateFileSizeMB
        )
        XCTAssertGreaterThan(
            PhotoQualityMode.balanced.approximateFileSizeMB,
            PhotoQualityMode.fast.approximateFileSizeMB
        )
    }

    // MARK: - Quality Prioritization Mapping Tests

    func testPhotoQualityMode_qualityPrioritization_qualityMode() {
        XCTAssertEqual(
            PhotoQualityMode.quality.qualityPrioritization,
            .quality
        )
    }

    func testPhotoQualityMode_qualityPrioritization_balancedMode() {
        XCTAssertEqual(
            PhotoQualityMode.balanced.qualityPrioritization,
            .balanced
        )
    }

    func testPhotoQualityMode_qualityPrioritization_fastMode() {
        XCTAssertEqual(
            PhotoQualityMode.fast.qualityPrioritization,
            .speed
        )
    }

    func testPhotoQualityMode_qualityPrioritizationRawValues() {
        // Verify the raw value ordering (speed < balanced < quality)
        XCTAssertLessThan(
            AVCapturePhotoOutput.QualityPrioritization.speed.rawValue,
            AVCapturePhotoOutput.QualityPrioritization.balanced.rawValue
        )
        XCTAssertLessThan(
            AVCapturePhotoOutput.QualityPrioritization.balanced.rawValue,
            AVCapturePhotoOutput.QualityPrioritization.quality.rawValue
        )
    }

    // MARK: - HDR Setting Tests

    func testPhotoQualityMode_enableHDR_qualityMode() {
        XCTAssertTrue(PhotoQualityMode.quality.enableHDR)
    }

    func testPhotoQualityMode_enableHDR_balancedMode() {
        XCTAssertTrue(PhotoQualityMode.balanced.enableHDR)
    }

    func testPhotoQualityMode_enableHDR_fastMode() {
        XCTAssertFalse(PhotoQualityMode.fast.enableHDR)
    }

    // MARK: - Deep Fusion Setting Tests

    func testPhotoQualityMode_enableDeepFusion_qualityMode() {
        XCTAssertTrue(PhotoQualityMode.quality.enableDeepFusion)
    }

    func testPhotoQualityMode_enableDeepFusion_balancedMode() {
        XCTAssertFalse(PhotoQualityMode.balanced.enableDeepFusion)
    }

    func testPhotoQualityMode_enableDeepFusion_fastMode() {
        XCTAssertFalse(PhotoQualityMode.fast.enableDeepFusion)
    }

    // MARK: - Default Values Tests

    func testDefaultValues_modeIsBalanced() {
        XCTAssertEqual(sut.mode, .balanced, "Default mode should be balanced")
    }

    // MARK: - Estimated File Size Tests

    func testEstimatedFileSizeBytes_qualityMode() {
        sut.mode = .quality
        XCTAssertEqual(sut.estimatedFileSizeBytes, 4_000_000)
    }

    func testEstimatedFileSizeBytes_balancedMode() {
        sut.mode = .balanced
        XCTAssertEqual(sut.estimatedFileSizeBytes, 2_000_000)
    }

    func testEstimatedFileSizeBytes_fastMode() {
        sut.mode = .fast
        XCTAssertEqual(sut.estimatedFileSizeBytes, 1_000_000)
    }

    func testEstimatedFileSizeFormatted_qualityMode() {
        sut.mode = .quality
        XCTAssertEqual(sut.estimatedFileSizeFormatted, "~4.0 MB")
    }

    func testEstimatedFileSizeFormatted_balancedMode() {
        sut.mode = .balanced
        XCTAssertEqual(sut.estimatedFileSizeFormatted, "~2.0 MB")
    }

    func testEstimatedFileSizeFormatted_fastMode() {
        sut.mode = .fast
        XCTAssertEqual(sut.estimatedFileSizeFormatted, "~1.0 MB")
    }

    // MARK: - Estimated Photos For Storage Tests

    func testEstimatedPhotosForStorage_qualityMode() {
        sut.mode = .quality
        // 2GB available - 500MB reserved = 1.5GB usable
        // 1.5GB / 4MB per photo = 375 photos
        let availableBytes: Int64 = 2_000_000_000
        let expectedPhotos = Int((availableBytes - 500_000_000) / Int64(4_000_000))
        XCTAssertEqual(sut.estimatedPhotosForStorage(availableBytes: availableBytes), expectedPhotos)
    }

    func testEstimatedPhotosForStorage_balancedMode() {
        sut.mode = .balanced
        let availableBytes: Int64 = 2_000_000_000
        let expectedPhotos = Int((availableBytes - 500_000_000) / Int64(2_000_000))
        XCTAssertEqual(sut.estimatedPhotosForStorage(availableBytes: availableBytes), expectedPhotos)
    }

    func testEstimatedPhotosForStorage_fastMode() {
        sut.mode = .fast
        let availableBytes: Int64 = 2_000_000_000
        let expectedPhotos = Int((availableBytes - 500_000_000) / Int64(1_000_000))
        XCTAssertEqual(sut.estimatedPhotosForStorage(availableBytes: availableBytes), expectedPhotos)
    }

    func testEstimatedPhotosForStorage_insufficientStorage() {
        sut.mode = .balanced
        // Less than 500MB reserved
        let availableBytes: Int64 = 400_000_000
        XCTAssertEqual(sut.estimatedPhotosForStorage(availableBytes: availableBytes), 0)
    }

    func testEstimatedPhotosForStorage_exactlyReservedAmount() {
        sut.mode = .balanced
        let availableBytes: Int64 = 500_000_000
        XCTAssertEqual(sut.estimatedPhotosForStorage(availableBytes: availableBytes), 0)
    }

    func testEstimatedPhotosForStorage_zeroBytes() {
        sut.mode = .balanced
        XCTAssertEqual(sut.estimatedPhotosForStorage(availableBytes: 0), 0)
    }

    func testEstimatedPhotosForStorage_morePhotosWithFastMode() {
        let availableBytes: Int64 = 5_000_000_000

        sut.mode = .quality
        let qualityPhotos = sut.estimatedPhotosForStorage(availableBytes: availableBytes)

        sut.mode = .balanced
        let balancedPhotos = sut.estimatedPhotosForStorage(availableBytes: availableBytes)

        sut.mode = .fast
        let fastPhotos = sut.estimatedPhotosForStorage(availableBytes: availableBytes)

        XCTAssertGreaterThan(fastPhotos, balancedPhotos)
        XCTAssertGreaterThan(balancedPhotos, qualityPhotos)
    }

    // MARK: - Persistence Tests

    func testPersistence_modeIsSaved() {
        sut.mode = .quality

        let newInstance = PhotoQualitySettings()

        XCTAssertEqual(newInstance.mode, .quality, "Mode should persist across instances")
    }

    func testPersistence_modeIsSavedOnChange() {
        sut.mode = .fast

        let savedValue = UserDefaults.standard.string(forKey: "photoQuality.mode")

        XCTAssertEqual(savedValue, "Fast")
    }

    func testPersistence_invalidSavedValue() {
        // Set an invalid value directly in UserDefaults
        UserDefaults.standard.set("InvalidMode", forKey: "photoQuality.mode")

        let newInstance = PhotoQualitySettings()

        // Should fall back to default
        XCTAssertEqual(newInstance.mode, .balanced)
    }

    func testPersistence_noSavedValue() {
        clearUserDefaults()

        let newInstance = PhotoQualitySettings()

        XCTAssertEqual(newInstance.mode, .balanced)
    }

    func testPersistence_allModes() {
        for mode in PhotoQualityMode.allCases {
            sut.mode = mode
            let newInstance = PhotoQualitySettings()
            XCTAssertEqual(newInstance.mode, mode, "Mode \(mode.rawValue) should persist")
        }
    }

    // MARK: - Codable Conformance Tests

    func testCodable_encodeAndDecode_qualityMode() throws {
        sut.mode = .quality

        let encoded = try JSONEncoder().encode(sut)
        let decoded = try JSONDecoder().decode(PhotoQualitySettings.self, from: encoded)

        XCTAssertEqual(decoded.mode, .quality)
    }

    func testCodable_encodeAndDecode_balancedMode() throws {
        sut.mode = .balanced

        let encoded = try JSONEncoder().encode(sut)
        let decoded = try JSONDecoder().decode(PhotoQualitySettings.self, from: encoded)

        XCTAssertEqual(decoded.mode, .balanced)
    }

    func testCodable_encodeAndDecode_fastMode() throws {
        sut.mode = .fast

        let encoded = try JSONEncoder().encode(sut)
        let decoded = try JSONDecoder().decode(PhotoQualitySettings.self, from: encoded)

        XCTAssertEqual(decoded.mode, .fast)
    }

    func testCodable_jsonFormat() throws {
        sut.mode = .quality

        let encoded = try JSONEncoder().encode(sut)
        let jsonString = String(data: encoded, encoding: .utf8)

        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("\"mode\""))
        XCTAssertTrue(jsonString!.contains("\"Quality\""))
    }

    func testCodable_decodeFromValidJSON() throws {
        let json = """
        {"mode":"Fast"}
        """
        let data = json.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PhotoQualitySettings.self, from: data)

        XCTAssertEqual(decoded.mode, .fast)
    }

    func testCodable_decodeFromInvalidJSON_throwsError() {
        let json = """
        {"mode":"InvalidMode"}
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(PhotoQualitySettings.self, from: data))
    }

    func testCodable_decodeFromMissingModeKey_throwsError() {
        let json = """
        {}
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(PhotoQualitySettings.self, from: data))
    }

    // MARK: - PhotoQualityMode Codable Tests

    func testPhotoQualityMode_codable_encodeAndDecode() throws {
        for mode in PhotoQualityMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PhotoQualityMode.self, from: encoded)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testPhotoQualityMode_codable_jsonFormat() throws {
        let encoded = try JSONEncoder().encode(PhotoQualityMode.quality)
        let jsonString = String(data: encoded, encoding: .utf8)

        XCTAssertEqual(jsonString, "\"Quality\"")
    }

    // MARK: - Mode Change Tests

    func testModeChange_updatesEstimatedFileSize() {
        sut.mode = .quality
        let qualitySize = sut.estimatedFileSizeBytes

        sut.mode = .fast
        let fastSize = sut.estimatedFileSizeBytes

        XCTAssertGreaterThan(qualitySize, fastSize)
    }

    func testModeChange_persistsImmediately() {
        sut.mode = .fast

        // Check UserDefaults immediately
        let savedValue = UserDefaults.standard.string(forKey: "photoQuality.mode")
        XCTAssertEqual(savedValue, "Fast")

        sut.mode = .quality
        let newSavedValue = UserDefaults.standard.string(forKey: "photoQuality.mode")
        XCTAssertEqual(newSavedValue, "Quality")
    }

    // MARK: - Edge Cases

    func testEstimatedPhotosForStorage_largeStorage() {
        sut.mode = .fast
        // 100GB
        let availableBytes: Int64 = 100_000_000_000
        let photos = sut.estimatedPhotosForStorage(availableBytes: availableBytes)

        XCTAssertGreaterThan(photos, 0)
        // Should be approximately (100GB - 500MB) / 1MB = ~99,500 photos
        XCTAssertGreaterThan(photos, 99_000)
    }

    func testPhotoQualityMode_equatable() {
        XCTAssertEqual(PhotoQualityMode.quality, PhotoQualityMode.quality)
        XCTAssertEqual(PhotoQualityMode.balanced, PhotoQualityMode.balanced)
        XCTAssertEqual(PhotoQualityMode.fast, PhotoQualityMode.fast)
        XCTAssertNotEqual(PhotoQualityMode.quality, PhotoQualityMode.balanced)
        XCTAssertNotEqual(PhotoQualityMode.balanced, PhotoQualityMode.fast)
        XCTAssertNotEqual(PhotoQualityMode.quality, PhotoQualityMode.fast)
    }

    func testPhotoQualityMode_hashable() {
        var set = Set<PhotoQualityMode>()
        set.insert(.quality)
        set.insert(.balanced)
        set.insert(.fast)

        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.quality))
        XCTAssertTrue(set.contains(.balanced))
        XCTAssertTrue(set.contains(.fast))
    }
}
