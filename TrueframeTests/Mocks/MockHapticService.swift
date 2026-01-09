// Mock implementation of HapticHeartbeatService for unit testing.

import Foundation
@testable import Trueframe

/// A mock haptic service that tracks haptic feedback without requiring hardware.
final class MockHapticService: HapticServiceProtocol {

    // MARK: - Tracking Properties

    var prepareCallCount = 0
    var playHeartbeatCallCount = 0
    var updateTempoCallCount = 0
    var endSessionCallCount = 0

    var lastTempoInterval: TimeInterval?
    var isPrepared = false
    var isSessionActive = false

    // MARK: - Configuration

    var prepareDelay: TimeInterval = 0

    // MARK: - Protocol Implementation

    func prepareForSession() async {
        if prepareDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(prepareDelay * 1_000_000_000))
        }

        prepareCallCount += 1
        isPrepared = true
        isSessionActive = true
    }

    func playHeartbeat() {
        guard isPrepared && isSessionActive else { return }
        playHeartbeatCallCount += 1
    }

    func updateTempo(interval: TimeInterval) {
        updateTempoCallCount += 1
        lastTempoInterval = interval
    }

    func endSession() {
        endSessionCallCount += 1
        isSessionActive = false
    }

    // MARK: - Test Helpers

    func reset() {
        prepareCallCount = 0
        playHeartbeatCallCount = 0
        updateTempoCallCount = 0
        endSessionCallCount = 0
        lastTempoInterval = nil
        isPrepared = false
        isSessionActive = false
        prepareDelay = 0
    }
}
