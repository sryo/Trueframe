#if DEBUG
import UIKit

/// Plays whole sessions on the simulator, which has neither a camera nor a proximity sensor.
enum DemoSession {
    static let launchArgument = "-demoSession"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    @MainActor
    static func makeCoordinator() -> SessionCoordinator {
        SessionCoordinator(
            engine: DemoCaptureEngine(),
            requestPermissions: { true },
            scorer: DemoScorer(),
            saver: DemoSaver(),
            proximity: DemoProximitySource()
        )
    }
}

@MainActor
final class DemoCaptureEngine: CaptureEngineProtocol {
    private var cadence: Task<Void, Never>?
    private var continuation: AsyncStream<CaptureEvent>.Continuation?

    func prewarm(_ configuration: CaptureConfiguration) async {}

    func start(_ configuration: CaptureConfiguration) async -> AsyncStream<CaptureEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.continuation = continuation
        cadence = Task {
            for index in 0... {
                try? await Task.sleep(for: .seconds(configuration.interval))
                guard !Task.isCancelled else { return }
                continuation.yield(.willCapture)
                continuation.yield(.captured(Self.asset(index)))
            }
        }
        return stream
    }

    func stop() async {
        cadence?.cancel()
        cadence = nil
        continuation?.finish()
        continuation = nil
    }

    private static func asset(_ index: Int) -> CapturedAsset {
        let hue = (Double(index) * 0.13).truncatingRemainder(dividingBy: 1)
        let size = CGSize(width: 240, height: 320)
        let preview = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                UIColor(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45, alpha: 1).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        return CapturedAsset(
            id: UUID(),
            fileData: preview.jpegData(compressionQuality: 0.6) ?? Data(),
            preview: preview,
            isProxy: false,
            capturedAt: .now
        )
    }
}

@MainActor
final class DemoProximitySource: ProximityEventSource {
    struct Schedule {
        var firstCover: Duration = .seconds(2)
        var covered: Duration = .seconds(4)
        var period: Duration = .seconds(10)
    }

    let events: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private let schedule: Schedule
    private var loop: Task<Void, Never>?

    init(schedule: Schedule = Schedule()) {
        self.schedule = schedule
        (events, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func start() {
        loop = Task { [schedule, continuation] in
            try? await Task.sleep(for: schedule.firstCover)
            while !Task.isCancelled {
                continuation.yield(true)
                try? await Task.sleep(for: schedule.covered)
                continuation.yield(false)
                try? await Task.sleep(for: schedule.period - schedule.covered)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        continuation.finish()
    }
}

/// Drops every third photo, starting with the second, so the demo shows misses.
private struct DemoScorer: PhotoScoring {
    func scores(for images: [UIImage?]) async -> [Float] {
        images.indices.map { $0 % 3 == 1 ? 0.1 : 0.9 }
    }
}

private struct DemoSaver: PhotoSaving {
    func save(_ items: [LibrarySaver.Item]) async -> Int { 0 }
}
#endif
