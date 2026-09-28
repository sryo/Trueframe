// Detects micro-windows of stillness between steps and breaths.
// Raw device motion needs no permission prompt.

@preconcurrency import CoreMotion
import os

/// The latest rotation sample for the current run of motion updates.
/// Samples tagged with an older run, or arriving after `end()`, are dropped:
/// Core Motion can still deliver a queued sample after updates stop.
struct StillnessReading: Sendable {
    private var run = 0
    private var isListening = false
    private var latestRotationMagnitude = Double.infinity

    var isStill: Bool { latestRotationMagnitude <= MotionMonitor.stillnessThreshold }

    mutating func begin() -> Int {
        run += 1
        isListening = true
        latestRotationMagnitude = .infinity
        return run
    }

    mutating func end() {
        isListening = false
        latestRotationMagnitude = .infinity
    }

    mutating func record(_ magnitude: Double, run sampleRun: Int) {
        guard isListening, sampleRun == run else { return }
        latestRotationMagnitude = magnitude
    }
}

/// Owned and driven by a single actor, so start and stop never race each other.
final class MotionMonitor {
    /// Rotation-rate magnitude (rad/s) below which the device counts as still.
    /// Angular velocity dominates motion blur at chest-hold distances.
    static let stillnessThreshold = 0.35

    private let manager = CMMotionManager()
    private let updateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.sryo.trueframe.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let reading = OSAllocatedUnfairLock(initialState: StillnessReading())

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        let run = reading.withLock { $0.begin() }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: updateQueue) { [reading] motion, _ in
            guard let rate = motion?.rotationRate else { return }
            let magnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            reading.withLock { $0.record(magnitude, run: run) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reading.withLock { $0.end() }
    }

    /// Waits up to `timeout` for the device to settle below the stillness
    /// threshold, then returns either way. The capture cadence has a floor,
    /// so a constantly moving user still gets photos.
    func waitForStillness(timeout: Duration, isolation: isolated (any Actor)? = #isolation) async {
        guard manager.isDeviceMotionActive else { return }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if reading.withLock({ $0.isStill }) { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
