// Manages capture session lifecycle.

import Combine
import SwiftUI
import UIKit

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var photoCount = 0

    private static let maxDarkFrames = 3
    private static let smudgeCheckInterval: TimeInterval = 3.0  // Check every 3 seconds

    private var cameraService: CameraService?
    private let hapticService = HapticHeartbeatService()
    private let storageMonitor = StorageMonitor()
    private let photoCache = PhotoCache.shared
    private let livePhotoService = LivePhotoService.shared
    private let photoAnalyzer = PhotoAnalyzer.shared

    private var captureTask: Task<Void, Never>?
    private var smudgeCheckTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var photoIDs: [UUID] = []  // Lightweight IDs instead of full UIImages
    private weak var appState: AppState?
    private var hasEnded = false
    private var consecutiveDarkFrames = 0
    private var memoryWarningObserver: NSObjectProtocol?

    // Settings-driven values
    private let maxPhotoCount = 50
    private var captureInterval: Double { appState?.captureSettings.captureInterval ?? 1.0 }
    private var livePhotosEnabled: Bool { appState?.captureSettings.livePhotosEnabled ?? false }
    private var smartSelectionEnabled: Bool { appState?.captureSettings.smartSelectionEnabled ?? true }

    func onAppear(appState: AppState) {
        self.appState = appState
        self.cameraService = appState.cameraService
        self.hasEnded = false

        // Register for memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.photoCache.handleMemoryWarning()
            }
        }

        // Proximity observer using Combine
        NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)
            .filter { _ in !UIDevice.current.proximityState }
            .sink { [weak self] _ in self?.endCaptureSession() }
            .store(in: &cancellables)

        cameraService?.capturedPhoto
            .receive(on: DispatchQueue.main)
            .sink { [weak self] photo in self?.handleCapturedPhoto(photo) }
            .store(in: &cancellables)

        storageMonitor.startMonitoring()
        Task { await hapticService.prepareForSession() }
        startCaptureSession()
        startSmudgeDetection()
    }

    func onDisappear() {
        captureTask?.cancel()
        captureTask = nil
        smudgeCheckTask?.cancel()
        smudgeCheckTask = nil
        // Only tear down camera if we haven't already in endCaptureSession
        if !hasEnded {
            Task { await cameraService?.tearDown() }
        }
        storageMonitor.stopMonitoring()
        hapticService.endSession()
        cancellables.removeAll()

        // Clear smudge states on disappear
        appState?.cameraSelectionSettings.clearSmudgeStates()

        // Remove memory warning observer
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
    }

    private func startCaptureSession() {
        guard !isCapturing else { return }

        isCapturing = true
        photoCount = 0
        photoIDs = []
        consecutiveDarkFrames = 0

        // Update haptic tempo based on capture interval
        hapticService.updateTempo(interval: captureInterval)

        // Start a new session in the photo cache
        Task {
            _ = await photoCache.startSession()
        }

        captureTask = Task {
            guard let cameraService = cameraService else { return }

            if let settings = appState?.cameraSelectionSettings {
                await cameraService.updateCameraSettings(
                    wide: settings.wideEnabled,
                    ultrawide: settings.ultrawideEnabled,
                    telephoto: settings.telephotoEnabled,
                    flash: settings.flashEnabled
                )
            }
            try? await cameraService.configure(for: .back)
            await runCaptureLoop()
        }
    }

    private func endCaptureSession() {
        guard isCapturing, !hasEnded else { return }

        hasEnded = true
        isCapturing = false
        captureTask?.cancel()
        captureTask = nil

        Task {
            // Wait briefly for any in-flight capture to complete
            try? await Task.sleep(for: .milliseconds(100))

            await cameraService?.tearDown()

            // Get thumbnails from cache for animation (memory-efficient)
            var thumbnails = await photoCache.allThumbnails()

            // Apply smart selection if enabled
            if smartSelectionEnabled && thumbnails.count > 5 {
                // Rank photos by quality and keep the best ones
                let ranked = await photoAnalyzer.analyzeAndRank(thumbnails)
                let sortedByScore = ranked.sorted { $0.score.overallScore > $1.score.overallScore }
                // Keep top 60% of photos, minimum 5
                let keepCount = max(5, Int(Double(thumbnails.count) * 0.6))
                thumbnails = Array(sortedByScore.prefix(keepCount).map { $0.image })
            }

            // Live Photos disabled - AVAssetWriterInputMetadataAdaptor API changed in iOS 26
            // TODO: Fix Live Photo creation for iOS 26+

            appState?.endCaptureSession(photos: thumbnails)
        }
    }

    private func runCaptureLoop() async {
        guard !Task.isCancelled && isCapturing else { return }
        guard storageMonitor.hasAdequateSpace else {
            endCaptureSession()
            return
        }

        // For fast intervals (<1s), use video frame capture instead of photo
        let isBurstMode = captureInterval < 1.0

        if isBurstMode {
            await runBurstCaptureLoop()
        } else {
            await runPhotoCaptureLoop()
        }
    }

    private func runPhotoCaptureLoop() async {
        // Capture first photo immediately
        try? await cameraService?.capturePhoto()

        while !Task.isCancelled && isCapturing {
            try? await Task.sleep(for: .seconds(captureInterval))

            guard !Task.isCancelled && isCapturing else { break }
            guard storageMonitor.hasAdequateSpace else {
                endCaptureSession()
                return
            }

            try? await cameraService?.capturePhoto()
        }
    }

    private func runBurstCaptureLoop() async {
        // Capture first frame immediately
        if let image = await cameraService?.captureFrame() {
            let captured = CapturedPhoto(image: image)
            handleCapturedPhoto(captured)
        }

        while !Task.isCancelled && isCapturing {
            try? await Task.sleep(for: .seconds(captureInterval))

            guard !Task.isCancelled && isCapturing else { break }
            guard storageMonitor.hasAdequateSpace else {
                endCaptureSession()
                return
            }

            if let image = await cameraService?.captureFrame() {
                let captured = CapturedPhoto(image: image)
                handleCapturedPhoto(captured)
            }
        }
    }

    private func handleCapturedPhoto(_ photo: CapturedPhoto) {
        guard !hasEnded else { return }

        if photo.image.isPitchBlack {
            consecutiveDarkFrames += 1
            if consecutiveDarkFrames >= Self.maxDarkFrames {
                endCaptureSession()
            }
            return
        }

        consecutiveDarkFrames = 0
        hapticService.playHeartbeat()

        // Store to disk cache and check limits
        let maxPhotos = maxPhotoCount
        Task {
            let photoID = await photoCache.store(photo.image, id: photo.id)
            await MainActor.run { [weak self] in
                guard let self, !self.hasEnded else { return }
                self.photoIDs.append(photoID)
                self.photoCount = self.photoIDs.count

                // Check limit after updating count
                if self.photoCount >= maxPhotos {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.endCaptureSession()
                }
            }
        }
    }

    // MARK: - Lens Smudge Detection

    private func startSmudgeDetection() {
        // Only run on iOS 26+ where DetectLensSmudgeRequest is available
        guard #available(iOS 26.0, *) else { return }

        smudgeCheckTask = Task {
            while !Task.isCancelled && isCapturing {
                await checkCurrentLensForSmudge()
                try? await Task.sleep(for: .seconds(Self.smudgeCheckInterval))
            }
        }
    }

    private func checkCurrentLensForSmudge() async {
        guard let cameraService = cameraService,
              let settings = appState?.cameraSelectionSettings else { return }

        // Capture a frame for smudge analysis
        guard let frame = await cameraService.captureFrame() else { return }

        // Run smudge detection
        let result = await photoAnalyzer.detectLensSmudge(frame)

        // Update the smudge state for the currently selected camera
        await MainActor.run {
            settings.setSmudged(settings.selectedCamera, isSmudged: result.isSmudged)
        }
    }
}
