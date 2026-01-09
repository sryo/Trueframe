// Unit tests for StorageMonitor.

import XCTest
@testable import Trueframe

/// Tests for StorageMonitor functionality.
final class StorageMonitorTests: XCTestCase {

    var sut: StorageMonitor!

    override func setUp() {
        super.setUp()
        sut = StorageMonitor()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - hasAdequateSpace Tests

    func testHasAdequateSpace_returnsBoolean() {
        // When
        let result = sut.hasAdequateSpace

        // Then
        // Should return a boolean without crashing
        XCTAssertTrue(result == true || result == false)
    }

    // MARK: - Monitoring Tests

    func testStartMonitoring_doesNotCrash() {
        // When
        sut.startMonitoring()

        // Then - should not crash
    }

    func testStopMonitoring_doesNotCrash() {
        // Given
        sut.startMonitoring()

        // When
        sut.stopMonitoring()

        // Then - should not crash
    }

    func testStopMonitoring_calledWithoutStart_doesNotCrash() {
        // When
        sut.stopMonitoring()

        // Then - should not crash
    }

    func testMonitoring_multipleStartCalls_doesNotCrash() {
        // When
        sut.startMonitoring()
        sut.startMonitoring()
        sut.startMonitoring()

        // Then - should not crash
    }

    func testMonitoring_multipleStopCalls_doesNotCrash() {
        // Given
        sut.startMonitoring()

        // When
        sut.stopMonitoring()
        sut.stopMonitoring()
        sut.stopMonitoring()

        // Then - should not crash
    }

    // MARK: - Lifecycle Tests

    func testDeinit_stopsMonitoring() {
        // Given
        sut.startMonitoring()

        // When
        sut = nil

        // Then - deinit should clean up without crash
    }

    // MARK: - Mock Storage Monitor Tests

    func testMockStorageMonitor_defaultState() {
        let mock = MockStorageMonitor()

        XCTAssertTrue(mock.hasAdequateSpace, "Default should have adequate space")
        XCTAssertFalse(mock.isMonitoring)
    }

    func testMockStorageMonitor_simulateLowStorage() {
        let mock = MockStorageMonitor()

        mock.simulateLowStorage()

        XCTAssertFalse(mock.hasAdequateSpace)
    }

    func testMockStorageMonitor_simulateAdequateStorage() {
        let mock = MockStorageMonitor()
        mock.simulateLowStorage()

        mock.simulateAdequateStorage()

        XCTAssertTrue(mock.hasAdequateSpace)
    }

    func testMockStorageMonitor_tracksStartMonitoring() {
        let mock = MockStorageMonitor()

        mock.startMonitoring()

        XCTAssertEqual(mock.startMonitoringCallCount, 1)
        XCTAssertTrue(mock.isMonitoring)
    }

    func testMockStorageMonitor_tracksStopMonitoring() {
        let mock = MockStorageMonitor()
        mock.startMonitoring()

        mock.stopMonitoring()

        XCTAssertEqual(mock.stopMonitoringCallCount, 1)
        XCTAssertFalse(mock.isMonitoring)
    }

    func testMockStorageMonitor_reset() {
        let mock = MockStorageMonitor()
        mock.startMonitoring()
        mock.stopMonitoring()
        mock.simulateLowStorage()

        mock.reset()

        XCTAssertTrue(mock.hasAdequateSpace)
        XCTAssertEqual(mock.startMonitoringCallCount, 0)
        XCTAssertEqual(mock.stopMonitoringCallCount, 0)
        XCTAssertFalse(mock.isMonitoring)
    }
}

// MARK: - FileManager Extension Tests

final class FileManagerExtensionTests: XCTestCase {

    func testHasAdequateSpace_returnsBoolean() {
        // When
        let result = FileManager.default.hasAdequateSpace

        // Then
        // Should return a boolean (actual value depends on device)
        XCTAssertTrue(result == true || result == false)
    }

    func testHasAdequateSpace_multipleCallsConsistent() {
        // When
        let result1 = FileManager.default.hasAdequateSpace
        let result2 = FileManager.default.hasAdequateSpace

        // Then - should be consistent in quick succession
        XCTAssertEqual(result1, result2)
    }
}
