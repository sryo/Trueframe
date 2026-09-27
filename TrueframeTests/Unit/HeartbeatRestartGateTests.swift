import XCTest
@testable import Trueframe

final class HeartbeatRestartGateTests: XCTestCase {

    func testRestart_isCurrentUntilSomethingElseHappens() {
        var gate = HeartbeatRestartGate()

        let token = gate.beginRestart()

        XCTAssertNotNil(token)
        XCTAssertTrue(gate.isCurrent(token!))
    }

    func testStopWhileRestarting_invalidatesTheRestart() {
        var gate = HeartbeatRestartGate()
        let token = gate.beginRestart()!

        gate.stop()

        XCTAssertFalse(gate.isCurrent(token), "A stop between reset and restart would revive a stopped engine")
    }

    func testRestartAfterStop_isRefused() {
        var gate = HeartbeatRestartGate()
        gate.stop()

        XCTAssertNil(gate.beginRestart())
    }

    func testNewerRestart_supersedesAnOlderOne() {
        var gate = HeartbeatRestartGate()
        let older = gate.beginRestart()!

        let newer = gate.beginRestart()!

        XCTAssertFalse(gate.isCurrent(older))
        XCTAssertTrue(gate.isCurrent(newer))
    }
}
