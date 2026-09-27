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

    private var continuation: AsyncStream<CaptureEvent>.Continuation?

    func prewarm(_ configuration: CaptureConfiguration) async {
        prewarmCallCount += 1
        lastConfiguration = configuration
    }

    func start(_ configuration: CaptureConfiguration) async -> AsyncStream<CaptureEvent> {
        startCallCount += 1
        lastConfiguration = configuration
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.continuation = continuation
        return stream
    }

    func stop() async {
        stopCallCount += 1
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Test Controls

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
