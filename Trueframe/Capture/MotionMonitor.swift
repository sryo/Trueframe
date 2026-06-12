// Detects micro-windows of stillness between steps and breaths.
// Raw device motion needs no permission prompt.

@preconcurrency import CoreMotion

actor MotionMonitor {
    /// Rotation-rate magnitude (rad/s) below which the device counts as still.
    /// Angular velocity dominates motion blur at chest-hold distances.
    static let stillnessThreshold = 0.35

    private let manager = CMMotionManager()
    private let updateQueue = OperationQueue()
    private var latestRotationMagnitude = Double.infinity

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: updateQueue) { [weak self] motion, _ in
            guard let self, let rate = motion?.rotationRate else { return }
            let magnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            Task { await self.update(magnitude) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        latestRotationMagnitude = .infinity
    }

    /// Waits up to `timeout` for the device to settle below the stillness
    /// threshold, then returns either way - the capture cadence has a floor,
    /// so a constantly moving user still gets photos.
    func waitForStillness(timeout: Duration) async {
        guard manager.isDeviceMotionActive else { return }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if latestRotationMagnitude <= Self.stillnessThreshold { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func update(_ magnitude: Double) {
        latestRotationMagnitude = magnitude
    }
}
