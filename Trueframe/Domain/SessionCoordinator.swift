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
    /// What curation decided about each of `sessionPreviews`; nil until scoring answers.
    private(set) var verdict: Verdict?

    let captureSettings = CaptureSettings()
    let cameraSelectionSettings = CameraSelectionSettings()

    var isCapturing: Bool { phase == .capturing || phase == .ending }
    var isCelebrating: Bool { phase == .celebrating }

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
    @ObservationIgnored private var curation: Task<Curation, Never>?
    /// Bumped by every new session, so work left over from an interrupted one
    /// can tell it no longer owns the screen or the store.
    @ObservationIgnored private var session = 0

    private struct Curation {
        let entries: [SessionStore.Entry]
        let selected: [Int]
    }

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
        guard phase == .idle || phase == .celebrating || phase == .saving,
              hasPermissions, FileManager.default.hasAdequateSpace else { return }
        let interrupting = phase != .idle
        if phase == .celebrating {
            // Nobody will finish the animation now, so its save starts here;
            // in .saving the save is already running and notices the handover
            startSave()
        }
        session += 1
        phase = .capturing
        consecutiveDarkFrames = 0
        capturedCount = 0
        keptCount = nil
        clearCelebrationState()

        let configuration = currentConfiguration()
        eventTask = Task { await runSession(configuration, detachingPrevious: interrupting) }
    }

    /// Returns once the engine has drained and the session has settled.
    func endSession() async {
        guard phase == .capturing else { return }
        await stopCapturing()
        await eventTask?.value
    }

    func celebrationHandedOff() {
        guard phase == .celebrating else { return }
        phase = .saving
        startSave()
    }

    private func startSave() {
        let curation = curation, session = session
        saveTask = Task { await save(curation, session: session) }
    }

    private func save(_ curation: Task<Curation, Never>?, session: Int) async {
        let chosen = await curation?.value
        let items = await curatedItems(chosen)
        // The photo library may take arbitrarily long to answer; the items
        // are already in memory, so the next session need not wait for it
        if !items.isEmpty {
            libraryWrite = Task { await writeToLibrary(items) }
        }
        if session == self.session {
            keptCount = items.count
            await resetToIdle(session: session)
        } else if let chosen {
            // Detached from the store, so these files are this save's to delete.
            // No kept count: its announcement would talk over "capturing"
            await store.removeFiles(for: chosen.entries.map(\.id))
        }
    }

    // Everything from first beat to teardown runs in this one task, so the
    // drain after stop() is consumed and teardown happens exactly once.
    private func runSession(_ configuration: CaptureConfiguration, detachingPrevious: Bool) async {
        if detachingPrevious {
            // The interrupted session's save still reads these files
            await store.detachSession()
        } else {
            await store.clearSession()
        }
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

        let entries = await store.allEntries()
        let previews = entries.compactMap(\.preview)
        if previews.isEmpty {
            await resetToIdle(session: session)
        } else {
            sessionPreviews = previews
            phase = .celebrating
            // Scored now, so the animation can show only what's kept
            let session = session
            curation = Task { await curate(entries, session: session) }
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
        if capturedCount >= CurationPolicy.maxPhotosPerSession || !FileManager.default.hasAdequateSpace {
            await stopCapturing()
        }
    }

    private func curate(_ entries: [SessionStore.Entry], session: Int) async -> Curation {
        let scores = await scorer.scores(for: entries.map(\.preview))
        let selected = CurationPolicy.selectionIndices(scores: scores)
        let kept = Set(selected)
        if session == self.session {
            let shown = entries.indices.filter { entries[$0].preview != nil }
            verdict = Verdict(kept: shown.map(kept.contains), scores: shown.map { scores[$0] })
        }
        return Curation(entries: entries, selected: selected)
    }

    private func curatedItems(_ curation: Curation?) async -> [LibrarySaver.Item] {
        guard let curation else { return [] }
        var items: [LibrarySaver.Item] = []
        for index in curation.selected {
            let entry = curation.entries[index]
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

    private func resetToIdle(session: Int) async {
        await store.clearSession()
        guard session == self.session else { return }
        clearCelebrationState()
        phase = .idle
        await engine.prewarm(currentConfiguration())
    }

    private func clearCelebrationState() {
        sessionPreviews = []
        verdict = nil
        curation = nil
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
