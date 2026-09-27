// Plays haptic feedback during capture.

import CoreHaptics
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
            print("[HapticHeartbeatService] Failed to prepare: \(error)")
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
    private let engine: CHHapticEngine
    private var player: CHHapticPatternPlayer?
    private var isStopped = false

    static func make() -> (any HeartbeatEngine)? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        do {
            return try CoreHapticsHeartbeat()
        } catch {
            print("[CoreHapticsHeartbeat] Failed to create engine: \(error)")
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
        isStopped = true
        player = nil
        engine.stop()
    }

    // After a reset the engine must be started again and its players recreated
    private func restart() {
        guard !isStopped else { return }
        player = nil
        Task { try? await start() }
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
