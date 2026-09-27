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

    func testStartAfterStop_listensOnAFreshStream() async {
        let monitor = ProximityMonitor()
        monitor.start()
        monitor.stop()

        monitor.start()
        let finishedEarly = expectation(description: "restarted events finish before stop")
        finishedEarly.isInverted = true
        let events = monitor.events
        let consumer = Task {
            for await _ in events {}
            finishedEarly.fulfill()
        }
        await fulfillment(of: [finishedEarly], timeout: 0.2)

        monitor.stop()
        await consumer.value
    }
}
