// Heartbeat that counts calls instead of driving Core Haptics.

@testable import Trueframe

@MainActor
final class FakeHeartbeat: HeartbeatPlaying {
    private(set) var prepareCount = 0
    private(set) var beatCount = 0
    private(set) var endCount = 0
    /// Stands in for the haptic engine running: set when prepare finishes, cleared by end.
    private(set) var isPrepared = false

    /// While true, prepareForSession() suspends until releasePrepare().
    var holdsPrepare = false
    private var prepareGate: CheckedContinuation<Void, Never>?

    func prepareForSession() async {
        prepareCount += 1
        if holdsPrepare {
            await withCheckedContinuation { prepareGate = $0 }
        }
        isPrepared = true
    }

    func playHeartbeat() {
        beatCount += 1
    }

    func endSession() {
        endCount += 1
        isPrepared = false
    }

    func releasePrepare() {
        holdsPrepare = false
        prepareGate?.resume()
        prepareGate = nil
    }
}
