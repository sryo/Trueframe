// Coordinates app state across screens.

import AVFoundation
import Combine
import Observation
import Photos
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppState {
    private(set) var isCapturing = false
    private(set) var sessionPhotos: [UIImage] = []
    private(set) var hasPermissions = false

    /// Shows tumble animation after capture
    private(set) var showingTumbleAnimation = false

    /// Pending video URL to save after tumble animation
    private var pendingVideoURL: URL?

    /// Current capture mode (Photo/Burst/Video)
    var captureMode: CaptureMode = .photo

    let cameraService = CameraService()
    let cameraSelectionSettings = CameraSelectionSettings()
    let photoQualitySettings = PhotoQualitySettings()
    let captureSettings = CaptureSettings()
    private let photoCache = PhotoCache.shared
    private let photoAnalyzer = PhotoAnalyzer.shared

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored
    private var isProximityMonitoringActive = false

    func checkAndRequestPermissions() async {
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

        // Request audio permission for video recording (optional, won't block)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        hasPermissions = cameraGranted && photosGranted

        if hasPermissions {
            setupProximityMonitoring()
            Task {
                await cameraService.setQualitySettings(photoQualitySettings)
                await cameraService.preWarm()
            }
        }
    }

    private func setupProximityMonitoring() {
        guard !isProximityMonitoringActive else { return }
        isProximityMonitoringActive = true
        UIDevice.current.isProximityMonitoringEnabled = true

        NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleProximityChange()
            }
            .store(in: &cancellables)
    }

    private func handleProximityChange() {
        let isCovered = UIDevice.current.proximityState
        if isCovered && !isCapturing {
            startCaptureSession()
        }
    }

    func startCaptureSession() {
        guard !isCapturing, hasPermissions else { return }
        isCapturing = true
        sessionPhotos = []
    }

    func endCaptureSession(photos: [UIImage]) {
        guard isCapturing else { return }
        isCapturing = false

        guard !photos.isEmpty else {
            resetSession()
            return
        }

        // Store photos for tumble animation and auto-save
        sessionPhotos = photos

        // Show tumble animation first
        showingTumbleAnimation = true
    }

    /// Called when tumble animation completes - triggers auto-save
    func tumbleAnimationComplete() {
        guard showingTumbleAnimation else { return }
        showingTumbleAnimation = false

        // Check if this was a video capture
        if let videoURL = pendingVideoURL {
            pendingVideoURL = nil
            Task { [weak self] in
                await self?.autoSaveVideo(videoURL)
            }
        } else {
            // Auto-save best photos - the core philosophy of Trueframe
            let photos = sessionPhotos
            guard !photos.isEmpty else {
                resetSession()
                return
            }
            Task { [weak self] in
                await self?.autoSaveBestPhotos(photos)
            }
        }
    }

    func endVideoSession(videoURL: URL?) {
        guard isCapturing else { return }
        isCapturing = false

        guard let videoURL else {
            resetSession()
            return
        }

        // Store video URL for later saving, generate thumbnail for animation
        pendingVideoURL = videoURL
        Task {
            let thumbnail = await generateVideoThumbnail(from: videoURL)
            await MainActor.run {
                if let thumbnail {
                    sessionPhotos = [thumbnail]
                }
                showingTumbleAnimation = true
            }
        }
    }

    /// Auto-save best photos to camera roll
    private func autoSaveBestPhotos(_ photos: [UIImage]) async {
        guard !photos.isEmpty else {
            resetSession()
            return
        }

        let ranked = await photoAnalyzer.analyzeAndRank(photos)
        let sortedByScore = ranked.sorted { $0.score.overallScore > $1.score.overallScore }

        let qualityThreshold: Float = 0.4
        var photosToSave = sortedByScore.filter { $0.score.overallScore >= qualityThreshold }

        if photosToSave.isEmpty && !sortedByScore.isEmpty {
            photosToSave = [sortedByScore[0]]
        }

        for rankedPhoto in photosToSave {
            do {
                try await savePhotoToLibrary(rankedPhoto.image)
            } catch {
                print("[AppState] Failed to save photo: \(error)")
            }
        }

        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        resetSession()
    }

    /// Auto-save video to camera roll
    private func autoSaveVideo(_ videoURL: URL) async {
        do {
            try await VideoRecordingService.shared.saveToPhotoLibrary(videoURL)
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            print("[AppState] Failed to save video: \(error)")
        }
        resetSession()
    }

    private func savePhotoToLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "PhotoSave", code: 1)
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            if let data = image.jpegData(compressionQuality: 0.9) {
                request.addResource(with: .photo, data: data, options: nil)
            }
            request.creationDate = Date()
        }
    }

    /// Generate a thumbnail from a video URL
    private func generateVideoThumbnail(from url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func resetSession() {
        sessionPhotos = []
        pendingVideoURL = nil

        Task {
            await photoCache.clearSession()
            await cameraService.preWarm()
        }
    }

    deinit {
        UIDevice.current.isProximityMonitoringEnabled = false
    }
}
