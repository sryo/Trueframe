// Haptic engine stand-in whose start can be held open.

@testable import Trueframe

@MainActor
final class FakeHeartbeatEngine: HeartbeatEngine {
    private(set) var isRunning = false
    private(set) var playCount = 0

    /// While true, start() suspends until releaseStart().
    var holdsStart = false
    private var startGate: CheckedContinuation<Void, Never>?

    func start() async throws {
        if holdsStart {
            await withCheckedContinuation { startGate = $0 }
        }
        isRunning = true
    }

    func play() throws {
        guard isRunning else { return }
        playCount += 1
    }

    func stop() {
        isRunning = false
    }

    func releaseStart() {
        holdsStart = false
        startGate?.resume()
        startGate = nil
    }
}
