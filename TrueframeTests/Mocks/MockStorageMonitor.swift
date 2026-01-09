// Mock implementation of StorageMonitor for unit testing.

import Foundation
@testable import Trueframe

/// Protocol for StorageMonitor to enable mocking
protocol StorageMonitorProtocol {
    var hasAdequateSpace: Bool { get }
    func startMonitoring()
    func stopMonitoring()
}

/// A mock storage monitor that allows controlling storage state for testing.
final class MockStorageMonitor: StorageMonitorProtocol {

    // MARK: - Controllable State

    var hasAdequateSpace: Bool = true

    // MARK: - Tracking Properties

    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0
    var isMonitoring = false

    // MARK: - Protocol Implementation

    func startMonitoring() {
        startMonitoringCallCount += 1
        isMonitoring = true
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        isMonitoring = false
    }

    // MARK: - Test Helpers

    func reset() {
        hasAdequateSpace = true
        startMonitoringCallCount = 0
        stopMonitoringCallCount = 0
        isMonitoring = false
    }

    /// Simulate running out of storage space
    func simulateLowStorage() {
        hasAdequateSpace = false
    }

    /// Simulate adequate storage space
    func simulateAdequateStorage() {
        hasAdequateSpace = true
    }
}

// MARK: - StorageMonitor Conformance
extension StorageMonitor: StorageMonitorProtocol {}
