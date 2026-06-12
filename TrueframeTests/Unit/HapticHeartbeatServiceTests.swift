// Unit tests for HapticHeartbeatService.

import XCTest
@testable import Trueframe

/// Tests for HapticHeartbeatService functionality.
/// Note: Haptic tests may require real device as simulator doesn't support haptics.
@MainActor
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

    // MARK: - Session Workflow Tests

    func testFullSessionWorkflow_doesNotCrash() async {
        // Prepare
        await sut.prepareForSession()

        // Play multiple heartbeats
        sut.playHeartbeat()
        sut.playHeartbeat()
        sut.playHeartbeat()

        // End session
        sut.endSession()
    }

}
