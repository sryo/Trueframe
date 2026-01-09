// Unit tests for HapticHeartbeatService.

import XCTest
@testable import Trueframe

/// Tests for HapticHeartbeatService functionality.
/// Note: Haptic tests may require real device as simulator doesn't support haptics.
final class HapticHeartbeatServiceTests: XCTestCase {

    var sut: HapticHeartbeatService!

    override func setUp() {
        super.setUp()
        sut = HapticHeartbeatService()
    }

    override func tearDown() {
        sut.endSession()
        sut = nil
        super.tearDown()
    }

    // MARK: - Protocol Conformance Tests

    func testHapticHeartbeatService_conformsToProtocol() {
        // Compile-time check
        let _: HapticServiceProtocol = sut
    }

    // MARK: - Lifecycle Tests

    func testPrepareForSession_doesNotCrash() async {
        // When/Then - should complete without crashing
        await sut.prepareForSession()
    }

    func testEndSession_doesNotCrash() {
        // When
        sut.endSession()

        // Then - should not crash
    }

    func testEndSession_withoutPrepare_doesNotCrash() {
        // When
        sut.endSession()

        // Then - should not crash
    }

    func testEndSession_calledMultipleTimes_doesNotCrash() {
        // When
        sut.endSession()
        sut.endSession()
        sut.endSession()

        // Then - should not crash
    }

    // MARK: - Heartbeat Tests

    func testPlayHeartbeat_beforePrepare_doesNotCrash() {
        // When
        sut.playHeartbeat()

        // Then - should not crash, but should do nothing
    }

    func testPlayHeartbeat_afterPrepare_doesNotCrash() async {
        // Given
        await sut.prepareForSession()

        // When
        sut.playHeartbeat()

        // Then - should not crash
    }

    func testPlayHeartbeat_afterEndSession_doesNotCrash() async {
        // Given
        await sut.prepareForSession()
        sut.endSession()

        // When
        sut.playHeartbeat()

        // Then - should not crash
    }

    // MARK: - Tempo Tests

    func testUpdateTempo_rapidInterval_doesNotCrash() {
        // When
        sut.updateTempo(interval: 0.3) // Rapid tier

        // Then - should not crash
    }

    func testUpdateTempo_moderateInterval_doesNotCrash() {
        // When
        sut.updateTempo(interval: 0.8) // Moderate tier

        // Then - should not crash
    }

    func testUpdateTempo_relaxedInterval_doesNotCrash() {
        // When
        sut.updateTempo(interval: 1.5) // Relaxed tier

        // Then - should not crash
    }

    func testUpdateTempo_slowInterval_doesNotCrash() {
        // When
        sut.updateTempo(interval: 3.0) // Slow tier

        // Then - should not crash
    }

    func testUpdateTempo_beforePrepare_doesNotCrash() {
        // When
        sut.updateTempo(interval: 1.0)

        // Then - should not crash
    }

    // MARK: - Session Workflow Tests

    func testFullSessionWorkflow_doesNotCrash() async {
        // Prepare
        await sut.prepareForSession()

        // Play multiple heartbeats at different tempos
        sut.updateTempo(interval: 0.5)
        sut.playHeartbeat()

        sut.updateTempo(interval: 1.0)
        sut.playHeartbeat()

        sut.updateTempo(interval: 2.0)
        sut.playHeartbeat()

        // End session
        sut.endSession()
    }

    // MARK: - Mock Tests

    func testMockHapticService_defaultState() {
        let mock = MockHapticService()

        XCTAssertFalse(mock.isPrepared)
        XCTAssertFalse(mock.isSessionActive)
        XCTAssertEqual(mock.prepareCallCount, 0)
    }

    func testMockHapticService_prepareForSession() async {
        let mock = MockHapticService()

        await mock.prepareForSession()

        XCTAssertEqual(mock.prepareCallCount, 1)
        XCTAssertTrue(mock.isPrepared)
        XCTAssertTrue(mock.isSessionActive)
    }

    func testMockHapticService_playHeartbeat() async {
        let mock = MockHapticService()
        await mock.prepareForSession()

        mock.playHeartbeat()
        mock.playHeartbeat()

        XCTAssertEqual(mock.playHeartbeatCallCount, 2)
    }

    func testMockHapticService_playHeartbeat_beforePrepare() {
        let mock = MockHapticService()

        mock.playHeartbeat()

        XCTAssertEqual(mock.playHeartbeatCallCount, 0, "Should not play when not prepared")
    }

    func testMockHapticService_updateTempo() {
        let mock = MockHapticService()

        mock.updateTempo(interval: 1.5)

        XCTAssertEqual(mock.updateTempoCallCount, 1)
        XCTAssertEqual(mock.lastTempoInterval, 1.5)
    }

    func testMockHapticService_endSession() async {
        let mock = MockHapticService()
        await mock.prepareForSession()

        mock.endSession()

        XCTAssertEqual(mock.endSessionCallCount, 1)
        XCTAssertFalse(mock.isSessionActive)
    }

    func testMockHapticService_reset() async {
        let mock = MockHapticService()
        await mock.prepareForSession()
        mock.playHeartbeat()
        mock.updateTempo(interval: 0.5)
        mock.endSession()

        mock.reset()

        XCTAssertEqual(mock.prepareCallCount, 0)
        XCTAssertEqual(mock.playHeartbeatCallCount, 0)
        XCTAssertEqual(mock.updateTempoCallCount, 0)
        XCTAssertEqual(mock.endSessionCallCount, 0)
        XCTAssertFalse(mock.isPrepared)
        XCTAssertFalse(mock.isSessionActive)
    }
}
