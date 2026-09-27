import CoreHaptics
import os
import UIKit

@MainActor
protocol HeartbeatPlaying: AnyObject {
    func prepareForSession() async
    func playHeartbeat()
    func endSession()
}

/// One session's haptic engine, loaded with the heartbeat pattern once started.
@MainActor
protocol HeartbeatEngine: AnyObject {
    func start() async throws
    func play() throws
    func stop()
}

@MainActor
final class HapticHeartbeatService: HeartbeatPlaying {
    private static let logger = Logger(subsystem: "com.trueframe.app", category: "HapticHeartbeatService")
    private let makeEngine: @MainActor () -> (any HeartbeatEngine)?
    private var engine: (any HeartbeatEngine)?
    private var sessionGeneration = 0

    /// makeEngine returns nil on hardware without haptics.
    init(makeEngine: @escaping @MainActor () -> (any HeartbeatEngine)? = CoreHapticsHeartbeat.make) {
        self.makeEngine = makeEngine
    }

    func prepareForSession() async {
        let generation = sessionGeneration
        guard let newEngine = makeEngine() else { return }
        do {
            try await newEngine.start()
            // The session may have ended while the engine was starting
            guard generation == sessionGeneration else {
                newEngine.stop()
                return
            }
            engine = newEngine
        } catch {
            Self.logger.error("Preparing haptics failed: \(error, privacy: .public)")
        }
    }

    func playHeartbeat() {
        try? engine?.play()
    }

    func endSession() {
        sessionGeneration += 1
        engine?.stop()
        engine = nil
    }
}

@MainActor
final class CoreHapticsHeartbeat: HeartbeatEngine {
    private static let logger = Logger(subsystem: "com.trueframe.app", category: "CoreHapticsHeartbeat")

    private let engine: CHHapticEngine
    private var player: CHHapticPatternPlayer?
    private var restartGate = HeartbeatRestartGate()

    static func make() -> (any HeartbeatEngine)? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        do {
            return try CoreHapticsHeartbeat()
        } catch {
            Self.logger.error("Creating the haptic engine failed: \(error, privacy: .public)")
            return nil
        }
    }

    private init() throws {
        engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.restart() }
        }
    }

    func start() async throws {
        try await engine.start()
        player = try engine.makePlayer(with: Self.heartbeatPattern())
    }

    func play() throws {
        try player?.start(atTime: CHHapticTimeImmediate)
    }

    func stop() {
        restartGate.stop()
        player = nil
        engine.stop()
    }

    // After a reset the engine must be started again and its players recreated.
    // stop() can land while the engine is starting, so the gate is rechecked after.
    private func restart() {
        guard let token = restartGate.beginRestart() else { return }
        player = nil
        Task { [weak self] in
            guard let self, restartGate.isCurrent(token) else { return }
            do {
                try await engine.start()
                try finishRestart(token)
            } catch {
                Self.logger.error("Restarting haptics failed: \(error, privacy: .public)")
            }
        }
    }

    private func finishRestart(_ token: Int) throws {
        guard restartGate.isCurrent(token) else {
            if restartGate.isStopped { engine.stop() }
            return
        }
        player = try engine.makePlayer(with: Self.heartbeatPattern())
    }

    private static func heartbeatPattern() throws -> CHHapticPattern {
        // Simple double-tap heartbeat: lub-dub
        let lub = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0
        )

        let dub = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
            ],
            relativeTime: 0.12
        )

        return try CHHapticPattern(events: [lub, dub], parameters: [])
    }
}

/// Decides whether an asynchronous engine restart is still wanted once it
/// resumes: stop() or a newer restart invalidates every earlier one.
struct HeartbeatRestartGate {
    private(set) var isStopped = false
    private var generation = 0

    mutating func beginRestart() -> Int? {
        guard !isStopped else { return nil }
        generation += 1
        return generation
    }

    func isCurrent(_ token: Int) -> Bool {
        !isStopped && token == generation
    }

    mutating func stop() {
        isStopped = true
        generation += 1
    }
}
