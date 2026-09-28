import Synchronization

/// A wait that ends on the first `resume()` or when the waiting task is cancelled,
/// whichever comes first. SwiftUI may never call an animation's completion once
/// its view is gone, so a wait on one must not rely on it alone.
final class ResumeOnce: Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<Void, Never>)
        case done
    }

    private let state = Mutex(State.pending)

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state in
                    if case .done = state { return true }
                    state = .waiting(continuation)
                    return false
                }
                if resumeNow || Task.isCancelled { resume() }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            resume()
        }
    }

    func resume() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            defer { state = .done }
            if case .waiting(let continuation) = state { return continuation }
            return nil
        }
        waiter?.resume()
    }
}
