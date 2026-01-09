// Creates Live Photos from capture sessions.

import AVFoundation
import Photos
import UIKit

enum LivePhotoError: Error, LocalizedError {
    case notSupported
    case captureSessionNotConfigured
    case movieFileCreationFailed
    case exportFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notSupported: return "Live Photos are not supported on this device"
        case .captureSessionNotConfigured: return "Camera session not configured for Live Photos"
        case .movieFileCreationFailed: return "Failed to create movie file"
        case .exportFailed: return "Failed to export Live Photo"
        case .saveFailed: return "Failed to save Live Photo"
        }
    }
}

actor LivePhotoService {
    static let shared = LivePhotoService()

    // MARK: - Constants

    private enum Constants {
        static let defaultFPS: Double = 15.0
        static let videoTimescale: CMTimeScale = 600
        static let keyPhotoFilename = "trueframe-live.jpg"
        static let movieFilename = "trueframe-live.mov"
        static let tempDirectoryName = "LivePhotos"
    }

    private let fileManager = FileManager.default
    private let tempDirectory: URL

    init() {
        // Safe fallback to temp directory if caches unavailable
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        tempDirectory = caches.appendingPathComponent(Constants.tempDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Live Photo from Image Sequence

    /// Create a Live Photo from a sequence of images (simulates the before/after effect)
    func createLivePhoto(
        keyPhoto: UIImage,
        beforeImages: [UIImage],
        afterImages: [UIImage],
        fps: Double = Constants.defaultFPS
    ) async throws -> (imageURL: URL, movieURL: URL) {
        // Save key photo as JPEG
        let photoID = UUID().uuidString
        let imageURL = tempDirectory.appendingPathComponent("\(photoID).jpg")
        let movieURL = tempDirectory.appendingPathComponent("\(photoID).mov")

        guard let imageData = keyPhoto.jpegData(compressionQuality: 0.9) else {
            throw LivePhotoError.movieFileCreationFailed
        }
        try imageData.write(to: imageURL)

        // Create movie from image sequence
        let allImages = beforeImages + [keyPhoto] + afterImages
        let keyPhotoIndex = beforeImages.count

        try await createMovie(
            from: allImages,
            at: movieURL,
            fps: fps,
            stillImageTime: CMTime(seconds: Double(keyPhotoIndex) / fps, preferredTimescale: Constants.videoTimescale)
        )

        return (imageURL, movieURL)
    }

    /// Create a movie file from an image sequence
    private func createMovie(
        from images: [UIImage],
        at outputURL: URL,
        fps: Double,
        stillImageTime: CMTime
    ) async throws {
        guard !images.isEmpty, let firstImage = images.first?.cgImage else {
            throw LivePhotoError.movieFileCreationFailed
        }

        let size = CGSize(width: firstImage.width, height: firstImage.height)

        // Remove existing file if present
        try? fileManager.removeItem(at: outputURL)

        // Setup asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height
            ]
        )

        writer.add(writerInput)

        // Add Live Photo metadata
        let metadataItem = AVMutableMetadataItem()
        metadataItem.key = "com.apple.quicktime.still-image-time" as NSString
        metadataItem.keySpace = .quickTimeMetadata
        metadataItem.value = NSNumber(value: stillImageTime.seconds)
        metadataItem.dataType = kCMMetadataBaseDataType_Float64 as String

        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil)
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        writer.add(metadataInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write frames
        let frameDuration = CMTime(seconds: 1.0 / fps, preferredTimescale: Constants.videoTimescale)

        for (index, image) in images.enumerated() {
            guard let cgImage = image.cgImage else { continue }

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            if let pixelBuffer = createPixelBuffer(from: cgImage, size: size) {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }

        // Write metadata for still image time
        let metadataGroup = AVTimedMetadataGroup(
            items: [metadataItem],
            timeRange: CMTimeRange(start: stillImageTime, duration: .zero)
        )
        metadataAdaptor.append(metadataGroup)

        writerInput.markAsFinished()
        metadataInput.markAsFinished()

        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? LivePhotoError.movieFileCreationFailed
        }
    }

    private func createPixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

        return buffer
    }

    // MARK: - Save to Photo Library

    /// Save a Live Photo to the photo library
    func saveLivePhoto(imageURL: URL, movieURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw LivePhotoError.saveFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()

            // Add photo
            let photoOptions = PHAssetResourceCreationOptions()
            photoOptions.originalFilename = Constants.keyPhotoFilename
            request.addResource(with: .photo, fileURL: imageURL, options: photoOptions)

            // Add movie companion
            let movieOptions = PHAssetResourceCreationOptions()
            movieOptions.originalFilename = Constants.movieFilename
            request.addResource(with: .pairedVideo, fileURL: movieURL, options: movieOptions)
        }
    }

    /// Create and save a Live Photo from a capture session's photos
    func createAndSaveLivePhoto(
        from photos: [UIImage],
        keyPhotoIndex: Int? = nil
    ) async throws {
        guard photos.count >= 3 else {
            throw LivePhotoError.movieFileCreationFailed
        }

        // Determine key photo (middle by default)
        let keyIndex = keyPhotoIndex ?? photos.count / 2
        let keyPhoto = photos[keyIndex]

        // Split into before and after
        let beforeImages = Array(photos.prefix(keyIndex))
        let afterImages = Array(photos.suffix(from: keyIndex + 1))

        let (imageURL, movieURL) = try await createLivePhoto(
            keyPhoto: keyPhoto,
            beforeImages: beforeImages,
            afterImages: afterImages
        )

        try await saveLivePhoto(imageURL: imageURL, movieURL: movieURL)

        // Cleanup temp files
        try? fileManager.removeItem(at: imageURL)
        try? fileManager.removeItem(at: movieURL)
    }

    // MARK: - Cleanup

    /// Clear all temporary Live Photo files
    func clearCache() {
        try? fileManager.removeItem(at: tempDirectory)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
}
