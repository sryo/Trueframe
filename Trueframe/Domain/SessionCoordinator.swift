// Owns the capture session lifecycle and coordinates all services.

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

    let captureSettings = CaptureSettings()
    let cameraSelectionSettings = CameraSelectionSettings()

    var isCapturing: Bool { phase == .capturing || phase == .ending }
    var showingTumbleAnimation: Bool { phase == .celebrating }

    let store = SessionStore()

    private let engine: any CaptureEngineProtocol
    private let requestPermissions: @Sendable () async -> Bool
    private let scorer = PhotoScorer()
    private let saver = LibrarySaver()
    private let haptics = HapticHeartbeatService()
    private let proximity = ProximityMonitor()

    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var consecutiveDarkFrames = 0

    init(
        engine: any CaptureEngineProtocol = CaptureEngine(),
        requestPermissions: @escaping @Sendable () async -> Bool = SystemPermissions.request
    ) {
        self.engine = engine
        self.requestPermissions = requestPermissions
    }

    // MARK: - Lifecycle

    func start() async {
        hasPermissions = await requestPermissions()
        guard hasPermissions else { return }

        proximity.start()
        await engine.prewarm(currentConfiguration())

        Task {
            for await covered in proximity.events {
                if covered {
                    beginSession()
                } else {
                    await endSession()
                }
            }
        }
    }

    // MARK: - Session Flow

    func beginSession() {
        guard phase == .idle, hasPermissions, FileManager.default.hasAdequateSpace else { return }
        phase = .capturing
        consecutiveDarkFrames = 0
        sessionPreviews = []

        let configuration = currentConfiguration()
        eventTask = Task {
            await store.clearSession()
            await haptics.prepareForSession()
            let events = await engine.start(configuration)
            for await event in events {
                await handle(event)
            }
        }
    }

    func endSession() async {
        guard phase == .capturing else { return }
        phase = .ending

        await engine.stop()
        haptics.endSession()
        eventTask?.cancel()
        eventTask = nil

        let previews = await store.previews
        if previews.isEmpty {
            await resetToIdle()
        } else {
            sessionPreviews = previews
            phase = .celebrating
        }
    }

    func tumbleAnimationComplete() {
        guard phase == .celebrating else { return }
        phase = .saving
        Task {
            await saveBestPhotos()
            await resetToIdle()
        }
    }

    // MARK: - Event Handling

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
                await endSession()
            }
            return
        }
        consecutiveDarkFrames = 0

        await store.add(asset)

        guard phase == .capturing else { return }
        if await store.count >= CurationPolicy.maxPhotosPerSession || !FileManager.default.hasAdequateSpace {
            await endSession()
        }
    }

    // MARK: - Saving

    private func saveBestPhotos() async {
        let entries = await store.allEntries()
        guard !entries.isEmpty else { return }

        let scores = await scorer.scores(for: entries.map(\.preview))
        let selected = CurationPolicy.selectionIndices(scores: scores)

        var items: [LibrarySaver.Item] = []
        for index in selected {
            let entry = entries[index]
            if let data = await store.fileData(for: entry.id) {
                items.append(LibrarySaver.Item(data: data, isProxy: entry.isProxy, capturedAt: entry.capturedAt))
            }
        }

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

    // MARK: - Helpers

    private func currentConfiguration() -> CaptureConfiguration {
        CaptureConfiguration(
            lens: cameraSelectionSettings.selectedCamera,
            flashEnabled: cameraSelectionSettings.flashEnabled,
            interval: captureSettings.captureInterval
        )
    }
}

// MARK: - System Permissions

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
