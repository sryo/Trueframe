// Protocol abstraction for VideoRecordingService to enable testing.

import AVFoundation
import Foundation
@testable import Trueframe

/// Protocol defining the video recording service interface for dependency injection and mocking.
protocol VideoRecordingServiceProtocol: AnyObject, Sendable {
    /// Configure the service with the specified video configuration.
    func configure(with config: VideoConfiguration) async throws

    /// Set the delegate for recording callbacks.
    func setDelegate(_ delegate: VideoRecordingDelegate?)

    /// Start recording video.
    func startRecording() async throws

    /// Stop recording and return the output URL when file is finalized.
    func stopRecording() async -> URL?

    /// Save a video to the photo library.
    func saveToPhotoLibrary(_ videoURL: URL) async throws

    /// Get the current recording duration.
    var recordingDuration: TimeInterval { get async }

    /// Get the current recording file size.
    var recordingFileSize: Int64 { get async }

    /// Clean up resources.
    func tearDown() async

    /// Clear the cache directory.
    func clearCache()
}

// MARK: - VideoRecordingService Conformance

// VideoRecordingService already conforms to this protocol via its actor implementation
