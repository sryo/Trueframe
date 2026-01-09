// Processes photos in the background using BGContinuedProcessingTask.

import BackgroundTasks
import Photos
import UIKit

@available(iOS 26.0, *)
actor BackgroundMediaProcessor {
    static let shared = BackgroundMediaProcessor()

    /// Task identifier - must match Info.plist BGTaskSchedulerPermittedIdentifiers
    static let taskIdentifier = "com.trueframe.media-processing"

    private let photoAnalyzer = PhotoAnalyzer.shared

    private var currentTask: BGContinuedProcessingTask?

    private init() {}

    // MARK: - Task Registration

    /// Register the background task handler. Call once at app launch.
    @MainActor
    static func registerTaskHandler() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGContinuedProcessingTask else { return }
            Task {
                await shared.handleBackgroundTask(processingTask)
            }
        }
    }

    // MARK: - Photo Processing

    /// Process and save photos with background task support.
    /// - Parameters:
    ///   - photos: Array of captured photos to process
    ///   - qualityThreshold: Minimum quality score (0-1) for auto-save. Default 0.4
    /// - Returns: Number of photos saved
    @discardableResult
    func processAndSavePhotos(_ photos: [UIImage], qualityThreshold: Float = 0.4) async -> Int {
        guard !photos.isEmpty else { return 0 }

        // Create and submit the background task request
        let photoCount = photos.count
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "Processing Photos",
            subtitle: "\(photoCount) photo\(photoCount == 1 ? "" : "s")"
        )

        // Request GPU access for Vision framework analysis
        if BGTaskScheduler.supportedResources.contains(.gpu) {
            request.requiredResources = .gpu
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundMediaProcessor] Failed to submit task: \(error)")
            // Fall back to foreground processing
            return await processPhotosDirectly(photos, qualityThreshold: qualityThreshold, task: nil)
        }

        // The actual processing happens in handleBackgroundTask when the system calls our handler
        // For now, we process directly since the task starts immediately in foreground
        return await processPhotosDirectly(photos, qualityThreshold: qualityThreshold, task: currentTask)
    }

    /// Direct photo processing with optional background task progress reporting
    private func processPhotosDirectly(
        _ photos: [UIImage],
        qualityThreshold: Float,
        task: BGContinuedProcessingTask?
    ) async -> Int {
        let totalSteps = 3 // Analyze, Select, Save
        var currentStep = 0

        func updateProgress(_ stepProgress: Double = 0) {
            let baseProgress = Double(currentStep) / Double(totalSteps)
            let stepContribution = stepProgress / Double(totalSteps)
            task?.progress.completedUnitCount = Int64((baseProgress + stepContribution) * 100)
        }

        task?.progress.totalUnitCount = 100

        // Check for cancellation
        var isCancelled = false
        task?.expirationHandler = {
            isCancelled = true
        }

        // Step 1: Analyze photos (0-33%)
        currentStep = 0
        updateProgress()

        let ranked = await photoAnalyzer.analyzeAndRank(photos)

        if isCancelled { return 0 }

        // Step 2: Select best photos (33-66%)
        currentStep = 1
        updateProgress()

        let sortedByScore = ranked.sorted { $0.score.overallScore > $1.score.overallScore }
        var photosToSave = sortedByScore.filter { $0.score.overallScore >= qualityThreshold }

        // Ensure at least 1 photo is saved
        if photosToSave.isEmpty && !sortedByScore.isEmpty {
            photosToSave = [sortedByScore[0]]
        }

        if isCancelled { return 0 }

        // Step 3: Save to camera roll (66-100%)
        currentStep = 2
        var savedCount = 0

        for (index, rankedPhoto) in photosToSave.enumerated() {
            if isCancelled { break }

            do {
                try await savePhotoToLibrary(rankedPhoto.image)
                savedCount += 1
                updateProgress(Double(index + 1) / Double(photosToSave.count))
            } catch {
                print("[BackgroundMediaProcessor] Failed to save photo: \(error)")
            }
        }

        // Mark complete
        task?.progress.completedUnitCount = 100
        task?.setTaskCompleted(success: !isCancelled && savedCount > 0)

        // Haptic feedback on completion
        let finalCount = savedCount
        await MainActor.run {
            if finalCount > 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }

        return savedCount
    }

    // MARK: - Video Processing

    /// Process and save video with background task support.
    /// - Parameter videoURL: URL of the recorded video
    /// - Returns: True if saved successfully
    @discardableResult
    func processAndSaveVideo(_ videoURL: URL) async -> Bool {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "Saving Video",
            subtitle: "Exporting to Camera Roll"
        )

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundMediaProcessor] Failed to submit video task: \(error)")
        }

        do {
            try await VideoRecordingService.shared.saveToPhotoLibrary(videoURL)
            currentTask?.setTaskCompleted(success: true)

            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            return true
        } catch {
            print("[BackgroundMediaProcessor] Failed to save video: \(error)")
            currentTask?.setTaskCompleted(success: false)
            return false
        }
    }

    // MARK: - Background Task Handler

    private func handleBackgroundTask(_ task: BGContinuedProcessingTask) async {
        currentTask = task

        // The task is already running from processAndSavePhotos/processAndSaveVideo
        // This handler is called by the system when transitioning to background

        task.expirationHandler = { [weak self] in
            Task {
                await self?.handleTaskExpiration()
            }
        }
    }

    private func handleTaskExpiration() async {
        // Clean up if task expires
        currentTask?.setTaskCompleted(success: false)
        currentTask = nil
    }

    // MARK: - Photo Library

    private func savePhotoToLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw MediaProcessingError.photoLibraryAccessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            if let data = image.jpegData(compressionQuality: 0.9) {
                request.addResource(with: .photo, data: data, options: nil)
            }
            request.creationDate = Date()
        }
    }
}

// MARK: - Errors

enum MediaProcessingError: Error, LocalizedError {
    case photoLibraryAccessDenied

    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photo library access denied"
        }
    }
}
