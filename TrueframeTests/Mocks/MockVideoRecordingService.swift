// Mock implementation of VideoRecordingService for unit testing.

import AVFoundation
import Foundation
@testable import Trueframe

/// A mock video recording service that simulates recording behavior for testing.
/// Allows fine-grained control over recording state, errors, and timing.
actor MockVideoRecordingService: @preconcurrency VideoRecordingServiceProtocol {

    // MARK: - State Tracking

    private(set) var isConfigured = false
    private(set) var isRecording = false
    private(set) var currentConfiguration: VideoConfiguration?
    private(set) var lastOutputURL: URL?
    private weak var delegate: VideoRecordingDelegate?

    // MARK: - Call Tracking (for test assertions)

    private(set) var configureCallCount = 0
    private(set) var startRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    private(set) var tearDownCallCount = 0
    private(set) var clearCacheCallCount = 0
    private(set) var saveToPhotoLibraryCallCount = 0
    private(set) var setDelegateCallCount = 0

    // MARK: - Configuration for Test Scenarios

    var shouldFailConfiguration = false
    var configurationError: VideoRecordingError = .deviceNotAvailable

    var shouldFailStartRecording = false
    var startRecordingError: VideoRecordingError = .notConfigured

    var shouldFailSaveToLibrary = false
    var saveError: VideoRecordingError = .saveFailed

    /// Delay to simulate async operations (in nanoseconds)
    var operationDelay: UInt64 = 0

    /// URL to return when stopRecording is called
    var stopRecordingURL: URL? = URL(fileURLWithPath: "/tmp/test-video.mov")

    /// Simulated recording duration
    var simulatedDuration: TimeInterval = 0

    /// Simulated file size
    var simulatedFileSize: Int64 = 0

    // MARK: - Protocol Implementation

    var recordingDuration: TimeInterval {
        simulatedDuration
    }

    var recordingFileSize: Int64 {
        simulatedFileSize
    }

    func configure(with config: VideoConfiguration) async throws {
        configureCallCount += 1

        if operationDelay > 0 {
            try? await Task.sleep(nanoseconds: operationDelay)
        }

        if shouldFailConfiguration {
            throw configurationError
        }

        currentConfiguration = config
        isConfigured = true
    }

    func setDelegate(_ delegate: VideoRecordingDelegate?) {
        setDelegateCallCount += 1
        self.delegate = delegate
    }

    func startRecording() async throws {
        startRecordingCallCount += 1

        if !isConfigured {
            throw VideoRecordingError.notConfigured
        }

        if isRecording {
            throw VideoRecordingError.recordingInProgress
        }

        if shouldFailStartRecording {
            throw startRecordingError
        }

        if operationDelay > 0 {
            try? await Task.sleep(nanoseconds: operationDelay)
        }

        isRecording = true
        let url = URL(fileURLWithPath: "/tmp/test-recording-\(UUID().uuidString.prefix(8)).mov")
        lastOutputURL = url

        // Notify delegate on main actor
        let videoDelegate = delegate
        Task { @MainActor in
            videoDelegate?.videoRecording(didStartAt: url)
        }
    }

    func stopRecording() async -> URL? {
        stopRecordingCallCount += 1

        guard isRecording else { return nil }

        if operationDelay > 0 {
            try? await Task.sleep(nanoseconds: operationDelay)
        }

        isRecording = false

        let outputURL = stopRecordingURL

        // Notify delegate on main actor
        let videoDelegate = delegate
        if let url = outputURL {
            Task { @MainActor in
                videoDelegate?.videoRecording(didFinishAt: url)
            }
        }

        return outputURL
    }

    func saveToPhotoLibrary(_ videoURL: URL) async throws {
        saveToPhotoLibraryCallCount += 1

        if operationDelay > 0 {
            try? await Task.sleep(nanoseconds: operationDelay)
        }

        if shouldFailSaveToLibrary {
            throw saveError
        }
    }

    func tearDown() async {
        tearDownCallCount += 1

        if operationDelay > 0 {
            try? await Task.sleep(nanoseconds: operationDelay)
        }

        isRecording = false
        isConfigured = false
        currentConfiguration = nil
        lastOutputURL = nil
    }

    nonisolated func clearCache() {
        // Note: In mock, we can't increment counter from nonisolated context
        // The counter tracking is done via other means in tests
    }

    // MARK: - Test Helpers

    /// Reset all tracking counters and state
    func reset() {
        configureCallCount = 0
        startRecordingCallCount = 0
        stopRecordingCallCount = 0
        tearDownCallCount = 0
        clearCacheCallCount = 0
        saveToPhotoLibraryCallCount = 0
        setDelegateCallCount = 0

        isConfigured = false
        isRecording = false
        currentConfiguration = nil
        lastOutputURL = nil
        delegate = nil

        shouldFailConfiguration = false
        shouldFailStartRecording = false
        shouldFailSaveToLibrary = false
        operationDelay = 0
        stopRecordingURL = URL(fileURLWithPath: "/tmp/test-video.mov")
        simulatedDuration = 0
        simulatedFileSize = 0
    }

    /// Simulate a recording error during recording (calls delegate)
    func simulateRecordingError(_ error: Error) async {
        isRecording = false
        let videoDelegate = delegate
        Task { @MainActor in
            videoDelegate?.videoRecording(didFailWithError: error)
        }
    }

    /// Simulate a duration update (calls delegate)
    func simulateDurationUpdate(_ duration: TimeInterval) async {
        simulatedDuration = duration
        let videoDelegate = delegate
        Task { @MainActor in
            videoDelegate?.videoRecording(didUpdateDuration: duration)
        }
    }

    /// Force set recording state for testing edge cases
    func forceSetRecordingState(_ recording: Bool) {
        isRecording = recording
    }

    /// Force set configured state for testing edge cases
    func forceSetConfiguredState(_ configured: Bool) {
        isConfigured = configured
    }

    /// Set whether configuration should fail
    func setShouldFailConfiguration(_ shouldFail: Bool, error: VideoRecordingError = .deviceNotAvailable) {
        shouldFailConfiguration = shouldFail
        configurationError = error
    }

    /// Set whether start recording should fail
    func setShouldFailStartRecording(_ shouldFail: Bool, error: VideoRecordingError = .notConfigured) {
        shouldFailStartRecording = shouldFail
        startRecordingError = error
    }

    /// Set whether save to library should fail
    func setShouldFailSaveToLibrary(_ shouldFail: Bool, error: VideoRecordingError = .saveFailed) {
        shouldFailSaveToLibrary = shouldFail
        saveError = error
    }
}

// MARK: - Mock Video Recording Delegate

/// A mock delegate that tracks all callback invocations.
@MainActor
final class MockVideoRecordingDelegate: VideoRecordingDelegate, @unchecked Sendable {

    // MARK: - Call Tracking

    private(set) var didStartAtURLs: [URL] = []
    private(set) var didFinishAtURLs: [URL] = []
    private(set) var didUpdateDurations: [TimeInterval] = []
    private(set) var didFailWithErrors: [Error] = []

    var didStartCallCount: Int { didStartAtURLs.count }
    var didFinishCallCount: Int { didFinishAtURLs.count }
    var didUpdateDurationCallCount: Int { didUpdateDurations.count }
    var didFailCallCount: Int { didFailWithErrors.count }

    // MARK: - Protocol Implementation

    func videoRecording(didStartAt url: URL) {
        didStartAtURLs.append(url)
    }

    func videoRecording(didFinishAt url: URL) {
        didFinishAtURLs.append(url)
    }

    func videoRecording(didUpdateDuration duration: TimeInterval) {
        didUpdateDurations.append(duration)
    }

    func videoRecording(didFailWithError error: Error) {
        didFailWithErrors.append(error)
    }

    // MARK: - Test Helpers

    func reset() {
        didStartAtURLs.removeAll()
        didFinishAtURLs.removeAll()
        didUpdateDurations.removeAll()
        didFailWithErrors.removeAll()
    }
}
