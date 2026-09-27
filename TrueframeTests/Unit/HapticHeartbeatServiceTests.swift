// Session lifecycle of the heartbeat service, run against a fake haptic engine.

import XCTest
@testable import Trueframe

@MainActor
final class HapticHeartbeatServiceTests: XCTestCase {

    func testPreparedSession_playsUntilEnded() async {
        let engine = FakeHeartbeatEngine()
        let sut = HapticHeartbeatService(makeEngine: { engine })

        await sut.prepareForSession()
        sut.playHeartbeat()
        sut.endSession()
        sut.playHeartbeat()

        XCTAssertEqual(engine.playCount, 1)
        XCTAssertFalse(engine.isRunning)
    }

    func testWithoutHapticHardware_playIsANoOp() async {
        let sut = HapticHeartbeatService(makeEngine: { nil })

        await sut.prepareForSession()
        sut.playHeartbeat()
        sut.endSession()
    }

    func testEndSession_whileEngineStarting_leavesEngineStopped() async {
        let engine = FakeHeartbeatEngine()
        engine.holdsStart = true
        let sut = HapticHeartbeatService(makeEngine: { engine })

        let preparing = Task { await sut.prepareForSession() }
        await Task.yield()
        sut.endSession()
        engine.releaseStart()
        await preparing.value
        sut.playHeartbeat()

        XCTAssertFalse(engine.isRunning, "Haptic engine left running after the session ended")
        XCTAssertEqual(engine.playCount, 0)
    }
}
