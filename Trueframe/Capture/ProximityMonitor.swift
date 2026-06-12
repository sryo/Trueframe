// The single source of proximity sensor events.

import UIKit

@MainActor
final class ProximityMonitor {
    /// Emits true when the sensor is covered, false when cleared. Debounced 50ms.
    let events: AsyncStream<Bool>

    private let continuation: AsyncStream<Bool>.Continuation
    private var observer: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    init() {
        (events, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func start() {
        guard observer == nil else { return }
        UIDevice.current.isProximityMonitoringEnabled = true

        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleEmit()
            }
        }
    }

    private func scheduleEmit() {
        debounceTask?.cancel()
        debounceTask = Task { [continuation] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            continuation.yield(UIDevice.current.proximityState)
        }
    }
}
