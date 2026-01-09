// Video recording capture screen.

import SwiftUI

struct VideoCaptureScreen: View {
    @Environment(AppState.self) private var appState
    @StateObject private var viewModel = VideoCaptureViewModel()

    var body: some View {
        Color.black.ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear { viewModel.onAppear(appState: appState) }
            .onDisappear { viewModel.onDisappear() }
    }
}

// MARK: - Video Capture ViewModel

@MainActor
final class VideoCaptureViewModel: ObservableObject {
    private var videoService: VideoRecordingService { VideoRecordingService.shared }
    private var delegateHandler: VideoDelegateHandler?

    private weak var appState: AppState?
    private var hasEnded = false
    private var isStarting = false
    private var isRecordingActive = false
    private var startTask: Task<Void, Never>?
    private var proximityObserver: NSObjectProtocol?

    func onAppear(appState: AppState) {
        self.appState = appState
        self.hasEnded = false
        self.isStarting = false
        self.isRecordingActive = false

        // Proximity observer to end recording when phone is lifted
        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if !UIDevice.current.proximityState {
                self?.endRecording()
            }
        }

        // Start recording immediately
        startRecording()
    }

    func onDisappear() {
        if let observer = proximityObserver {
            NotificationCenter.default.removeObserver(observer)
            proximityObserver = nil
        }

        startTask?.cancel()
        startTask = nil

        if !hasEnded {
            hasEnded = true
            let wasRecording = isRecordingActive
            isStarting = false
            isRecordingActive = false

            let handler = delegateHandler
            Task { [handler] in
                _ = handler
                if wasRecording {
                    _ = await videoService.stopRecording()
                }
                await videoService.setDelegate(nil)
                await videoService.tearDown()
            }
        }
    }

    private func startRecording() {
        guard !isStarting && !hasEnded else { return }
        isStarting = true

        startTask = Task {
            do {
                guard !Task.isCancelled && !hasEnded else {
                    isStarting = false
                    return
                }

                // Tear down CameraService first
                if let cameraService = appState?.cameraService {
                    await cameraService.tearDown()
                }

                guard !Task.isCancelled && !hasEnded else {
                    isStarting = false
                    return
                }

                // Create delegate
                let handler = VideoDelegateHandler(
                    onStart: {},
                    onFinish: { _ in },
                    onError: { [weak self] error in
                        print("[VideoCapture] Error: \(error)")
                        self?.endRecording()
                    }
                )
                self.delegateHandler = handler

                // Configure and start
                let service = videoService
                try await service.configure(with: .default)

                guard !Task.isCancelled && !hasEnded else {
                    isStarting = false
                    await service.tearDown()
                    return
                }

                await service.setDelegate(handler)
                try await service.startRecording()

                isStarting = false
                isRecordingActive = true

                // Haptic feedback on start
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.prepare()
                    haptic.notificationOccurred(.success)
                }

            } catch {
                isStarting = false
                print("[VideoCapture] Failed to start: \(error)")
                endRecording()
            }
        }
    }

    private func endRecording() {
        guard !hasEnded else { return }
        hasEnded = true

        startTask?.cancel()
        startTask = nil

        let wasRecording = isRecordingActive
        isStarting = false
        isRecordingActive = false

        // Haptic feedback on end
        if wasRecording {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        let handler = delegateHandler
        let capturedAppState = appState

        Task { [handler] in
            _ = handler

            var videoURL: URL? = nil
            if wasRecording {
                videoURL = await videoService.stopRecording()
            }

            await videoService.setDelegate(nil)
            await videoService.tearDown()

            await MainActor.run {
                capturedAppState?.endVideoSession(videoURL: videoURL)
            }
        }
    }
}

// MARK: - Video Delegate Handler

/// A Sendable delegate handler that can safely cross actor boundaries
final class VideoDelegateHandler: VideoRecordingDelegate, @unchecked Sendable {
    private let onStart: @MainActor () -> Void
    private let onFinish: @MainActor (URL) -> Void
    private let onError: @MainActor (Error) -> Void

    init(
        onStart: @escaping @MainActor () -> Void,
        onFinish: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.onStart = onStart
        self.onFinish = onFinish
        self.onError = onError
    }

    @MainActor func videoRecording(didStartAt url: URL) {
        onStart()
    }

    @MainActor func videoRecording(didFinishAt url: URL) {
        onFinish(url)
    }

    @MainActor func videoRecording(didUpdateDuration duration: TimeInterval) {
        // Duration is handled via polling in the ViewModel
    }

    @MainActor func videoRecording(didFailWithError error: Error) {
        onError(error)
    }
}

#Preview {
    VideoCaptureScreen()
        .environment(AppState())
}
