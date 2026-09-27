import UIKit

@MainActor
protocol ProximityEventSource: AnyObject {
    /// Emits true when the sensor is covered, false when cleared.
    /// Read it after start(): a start following stop() begins a fresh stream.
    var events: AsyncStream<Bool> { get }
    func start()
    /// Finishes the current events stream.
    func stop()
}

@MainActor
final class ProximityMonitor: ProximityEventSource {
    /// Emits true when the sensor is covered, false when cleared. Debounced 50ms.
    private(set) var events: AsyncStream<Bool>

    private var continuation: AsyncStream<Bool>.Continuation
    private var observer: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var isStopped = false

    init() {
        (events, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func start() {
        guard observer == nil else { return }
        if isStopped {
            (events, continuation) = AsyncStream.makeStream(of: Bool.self)
            isStopped = false
        }
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

    func stop() {
        isStopped = true
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        debounceTask?.cancel()
        debounceTask = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        continuation.finish()
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
