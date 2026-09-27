// Teardown of the proximity sensor stream.

import XCTest
@testable import Trueframe

@MainActor
final class ProximityMonitorTests: XCTestCase {

    func testStop_finishesEvents() async {
        let monitor = ProximityMonitor()
        monitor.start()
        let finished = expectation(description: "events finish")
        let consumer = Task {
            for await _ in monitor.events {}
            finished.fulfill()
        }

        monitor.stop()

        await fulfillment(of: [finished], timeout: 1)
        consumer.cancel()
    }
}
