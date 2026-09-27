// Heartbeat that counts calls instead of driving Core Haptics.

@testable import Trueframe

@MainActor
final class FakeHeartbeat: HeartbeatPlaying {
    private(set) var prepareCount = 0
    private(set) var beatCount = 0
    private(set) var endCount = 0

    func prepareForSession() async {
        prepareCount += 1
    }

    func playHeartbeat() {
        beatCount += 1
    }

    func endSession() {
        endCount += 1
    }
}
