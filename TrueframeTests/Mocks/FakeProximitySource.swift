// Proximity source that tests drive by hand.

@testable import Trueframe

@MainActor
final class FakeProximitySource: ProximityEventSource {
    let events: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private(set) var startCount = 0

    init() {
        (events, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func start() {
        startCount += 1
    }

    func send(covered: Bool) {
        continuation.yield(covered)
    }
}
