// Plays haptic feedback during capture.

import CoreHaptics
import UIKit

protocol HapticServiceProtocol: AnyObject {
    func prepareForSession() async
    func playHeartbeat()
    func updateTempo(interval: TimeInterval)
    func endSession()
}

final class HapticHeartbeatService: HapticServiceProtocol {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var isReady = false

    func prepareForSession() async {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let newEngine = try CHHapticEngine()
            newEngine.playsHapticsOnly = true
            newEngine.isAutoShutdownEnabled = true

            newEngine.resetHandler = { [weak self] in
                Task { @MainActor in self?.restart() }
            }

            try await newEngine.start()
            self.engine = newEngine
            self.player = try newEngine.makePlayer(with: createHeartbeatPattern())
            self.isReady = true
        } catch {
            print("[HapticHeartbeatService] Failed to prepare: \(error)")
        }
    }

    func playHeartbeat() {
        guard isReady else { return }
        try? player?.start(atTime: CHHapticTimeImmediate)
    }

    func updateTempo(interval: TimeInterval) {
        // Not used - consistent heartbeat feel
    }

    func endSession() {
        isReady = false
        player = nil
        engine?.stop()
        engine = nil
    }

    private func createHeartbeatPattern() throws -> CHHapticPattern {
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

    private func restart() {
        isReady = false
        Task { await prepareForSession() }
    }

    deinit {
        engine?.stop(completionHandler: nil)
    }
}
