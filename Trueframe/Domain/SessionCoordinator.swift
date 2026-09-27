import AVFoundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var phase: SessionPhase = .idle
    private(set) var sessionPreviews: [UIImage] = []
    private(set) var hasPermissions = false
    /// Photos kept into the store this session; dark frames never count.
    private(set) var capturedCount = 0
    /// How many photos saving picked from the last session; nil until it has picked.
    private(set) var keptCount: Int?

    let captureSettings = CaptureSettings()
    let cameraSelectionSettings = CameraSelectionSettings()

    var isCapturing: Bool { phase == .capturing || phase == .ending }
    var showingTumbleAnimation: Bool { phase == .celebrating }

    let store = SessionStore()

    private let engine: any CaptureEngineProtocol
    private let requestPermissions: @Sendable () async -> Bool
    private let scorer: any PhotoScoring
    private let saver: any PhotoSaving
    private let haptics: any HeartbeatPlaying
    private let proximity: any ProximityEventSource

    @ObservationIgnored private var proximityTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private(set) var saveTask: Task<Void, Never>?
    @ObservationIgnored private(set) var libraryWrite: Task<Void, Never>?
    @ObservationIgnored private var consecutiveDarkFrames = 0

    init(
        engine: any CaptureEngineProtocol = CaptureEngine(),
        requestPermissions: @escaping @Sendable () async -> Bool = SystemPermissions.request,
        scorer: any PhotoScoring = PhotoScorer(),
        saver: any PhotoSaving = LibrarySaver(),
        haptics: any HeartbeatPlaying = HapticHeartbeatService(),
        proximity: any ProximityEventSource = ProximityMonitor()
    ) {
        self.engine = engine
        self.requestPermissions = requestPermissions
        self.scorer = scorer
        self.saver = saver
        self.haptics = haptics
        self.proximity = proximity
    }

    func start() async {
        hasPermissions = await requestPermissions()
        guard hasPermissions else { return }

        guard proximityTask == nil else { return }

        proximity.start()
        proximityTask = Task { [weak self, events = proximity.events] in
            for await covered in events {
                // A stream delivers what it buffered even after cancellation
                guard let self, !Task.isCancelled else { return }
                if covered {
                    beginSession()
                } else {
                    await endSession()
                }
            }
        }
        await engine.prewarm(currentConfiguration())
    }

    func stop() {
        proximityTask?.cancel()
        proximityTask = nil
        proximity.stop()
    }

    func beginSession() {
        guard phase == .idle, hasPermissions, FileManager.default.hasAdequateSpace else { return }
        phase = .capturing
        consecutiveDarkFrames = 0
        capturedCount = 0
        keptCount = nil
        sessionPreviews = []

        let configuration = currentConfiguration()
        eventTask = Task { await runSession(configuration) }
    }

    /// Returns once the engine has drained and the session has settled.
    func endSession() async {
        guard phase == .capturing else { return }
        await stopCapturing()
        await eventTask?.value
    }

    func tumbleAnimationComplete() {
        guard phase == .celebrating else { return }
        phase = .saving
        saveTask = Task {
            let items = await curatedItems()
            keptCount = items.count
            // The photo library may take arbitrarily long to answer; the items
            // are already in memory, so the next session need not wait for it
            if !items.isEmpty {
                libraryWrite = Task { await writeToLibrary(items) }
            }
            await resetToIdle()
        }
    }

    // Everything from first beat to teardown runs in this one task, so the
    // drain after stop() is consumed and teardown happens exactly once.
    private func runSession(_ configuration: CaptureConfiguration) async {
        await store.clearSession()
        await haptics.prepareForSession()
        if phase == .capturing {
            // One beat at the moment of contact, before the first photo:
            // the answer to "is it working?" on a screen the user can't see
            haptics.playHeartbeat()
            let events = await engine.start(configuration)
            // A lift while the camera was starting may have stopped it before it ran
            if phase != .capturing {
                await engine.stop()
            }
            for await event in events {
                await handle(event)
            }
        }

        if phase == .capturing {
            await stopCapturing()
        }
        haptics.endSession()

        let previews = await store.previews
        if previews.isEmpty {
            await resetToIdle()
        } else {
            sessionPreviews = previews
            phase = .celebrating
        }
    }

    private func stopCapturing() async {
        phase = .ending
        await engine.stop()
    }

    private func handle(_ event: CaptureEvent) async {
        switch event {
        case .willCapture:
            haptics.playHeartbeat()
        case .captured(let asset):
            await handleCaptured(asset)
        }
    }

    private func handleCaptured(_ asset: CapturedAsset) async {
        // In-flight captures draining during .ending are still kept
        guard phase == .capturing || phase == .ending else { return }

        // Pitch-black frames mean the phone is face-down or pocketed
        if let preview = asset.preview, preview.isPitchBlack {
            guard phase == .capturing else { return }
            consecutiveDarkFrames += 1
            if consecutiveDarkFrames >= CurationPolicy.maxConsecutiveDarkFrames {
                await stopCapturing()
            }
            return
        }
        consecutiveDarkFrames = 0

        await store.add(asset)
        capturedCount += 1

        guard phase == .capturing else { return }
        if await store.count >= CurationPolicy.maxPhotosPerSession || !FileManager.default.hasAdequateSpace {
            await stopCapturing()
        }
    }

    private func curatedItems() async -> [LibrarySaver.Item] {
        let entries = await store.allEntries()
        guard !entries.isEmpty else { return [] }

        let scores = await scorer.scores(for: entries.map(\.preview))
        let selected = CurationPolicy.selectionIndices(scores: scores)

        var items: [LibrarySaver.Item] = []
        for index in selected {
            let entry = entries[index]
            if let data = await store.fileData(for: entry.id) {
                items.append(LibrarySaver.Item(data: data, isProxy: entry.isProxy, capturedAt: entry.capturedAt))
            }
        }

        return items
    }

    private func writeToLibrary(_ items: [LibrarySaver.Item]) async {
        let saved = await saver.save(items)
        if saved > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func resetToIdle() async {
        await store.clearSession()
        sessionPreviews = []
        phase = .idle
        await engine.prewarm(currentConfiguration())
    }

    private func currentConfiguration() -> CaptureConfiguration {
        CaptureConfiguration(
            lens: cameraSelectionSettings.selectedCamera,
            flashEnabled: cameraSelectionSettings.flashEnabled,
            interval: captureSettings.captureInterval
        )
    }
}

enum SystemPermissions {
    /// Camera capture plus add-only photo library access.
    @Sendable
    static func request() async -> Bool {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var cameraGranted = cameraStatus == .authorized
        if cameraStatus == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        }

        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var photosGranted = photoStatus == .authorized || photoStatus == .limited
        if photoStatus == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            photosGranted = newStatus == .authorized || newStatus == .limited
        }

        return cameraGranted && photosGranted
    }
}
