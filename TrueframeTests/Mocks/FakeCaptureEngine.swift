// Scriptable capture engine for coordinator tests.

import Foundation
import UIKit
@testable import Trueframe

/// A fake engine that lets tests emit capture events on demand.
@MainActor
final class FakeCaptureEngine: CaptureEngineProtocol {
    private(set) var prewarmCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastConfiguration: CaptureConfiguration?
    private(set) var isRunning = false

    /// Events yielded from stop() before the stream finishes, like in-flight captures draining.
    var eventsDrainedOnStop: [CaptureEvent] = []

    /// While true, start() suspends until releaseStart().
    var holdsStart = false
    private var startGate: CheckedContinuation<Void, Never>?

    private var continuation: AsyncStream<CaptureEvent>.Continuation?

    func prewarm(_ configuration: CaptureConfiguration) async {
        prewarmCallCount += 1
        lastConfiguration = configuration
    }

    func start(_ configuration: CaptureConfiguration) async -> AsyncStream<CaptureEvent> {
        startCallCount += 1
        lastConfiguration = configuration
        if holdsStart {
            await withCheckedContinuation { startGate = $0 }
        }
        isRunning = true
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.continuation = continuation
        return stream
    }

    func stop() async {
        stopCallCount += 1
        isRunning = false
        for event in eventsDrainedOnStop {
            continuation?.yield(event)
        }
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Test Controls

    func releaseStart() {
        holdsStart = false
        startGate?.resume()
        startGate = nil
    }

    /// Ends the stream from the engine's side, as a capture failure would.
    func finishStream() {
        isRunning = false
        continuation?.finish()
        continuation = nil
    }

    func emit(_ event: CaptureEvent) {
        continuation?.yield(event)
    }

    func emitCapturedPhoto(brightness: CGFloat = 0.5) {
        emit(.captured(Self.makeAsset(brightness: brightness)))
    }

    nonisolated static func makeAsset(brightness: CGFloat = 0.5, fileData: Data = Data([0xFF, 0xD8, 0xFF])) -> CapturedAsset {
        CapturedAsset(
            id: UUID(),
            fileData: fileData,
            preview: makeImage(brightness: brightness),
            isProxy: false,
            capturedAt: Date()
        )
    }

    nonisolated static func makeImage(brightness: CGFloat, size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: brightness, alpha: 1.0).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
