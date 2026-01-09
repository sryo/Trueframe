// Photo quality settings.

import AVFoundation
import Foundation
import Observation

enum PhotoQualityMode: String, CaseIterable, Identifiable, Codable {
    case quality = "Quality"
    case balanced = "Balanced"
    case fast = "Fast"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .quality: return "Best photos, larger files"
        case .balanced: return "Great photos, reasonable storage"
        case .fast: return "Quick capture, smaller files"
        }
    }

    var iconName: String {
        switch self {
        case .quality: return "sparkles"
        case .balanced: return "scale.3d"
        case .fast: return "bolt.fill"
        }
    }

    var approximateFileSizeMB: Double {
        switch self {
        case .quality: return 4.0
        case .balanced: return 2.0
        case .fast: return 1.0
        }
    }

    var qualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        switch self {
        case .quality: return .quality
        case .balanced: return .balanced
        case .fast: return .speed
        }
    }

}

// MARK: - Photo Quality Settings

@Observable
final class PhotoQualitySettings {

    private enum Keys {
        static let mode = "photoQuality.mode"
    }

    var mode: PhotoQualityMode = .balanced {
        didSet { saveSettings() }
    }

    // MARK: - Computed Properties

    var estimatedFileSizeFormatted: String {
        String(format: "~%.1f MB", mode.approximateFileSizeMB)
    }

    func estimatedPhotosForStorage(availableBytes: Int64) -> Int {
        let fileSizeBytes = Int(mode.approximateFileSizeMB * 1_000_000)
        guard fileSizeBytes > 0 else { return 0 }
        let usableBytes = max(0, availableBytes - 500_000_000) // Reserve 500MB
        return Int(usableBytes / Int64(fileSizeBytes))
    }

    // MARK: - Initialization

    init() {
        loadSettings()
    }

    // MARK: - Persistence

    func saveSettings() {
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
    }

    private func loadSettings() {
        if let rawValue = UserDefaults.standard.string(forKey: Keys.mode),
           let savedMode = PhotoQualityMode(rawValue: rawValue) {
            self.mode = savedMode
        }
    }

    // MARK: - AVFoundation Configuration

    func configurePhotoSettings(_ settings: AVCapturePhotoSettings, output: AVCapturePhotoOutput) {
        settings.maxPhotoDimensions = output.maxPhotoDimensions

        if output.maxPhotoQualityPrioritization.rawValue >= mode.qualityPrioritization.rawValue {
            settings.photoQualityPrioritization = mode.qualityPrioritization
        }
    }

    func createPhotoSettings(for output: AVCapturePhotoOutput, flashEnabled: Bool = false) -> AVCapturePhotoSettings {
        var settings: AVCapturePhotoSettings

        // Use HEIF for best compression
        if let heifCodec = output.availablePhotoCodecTypes.first(where: { $0 == .hevc }) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: heifCodec])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.flashMode = flashEnabled ? .on : .off
        configurePhotoSettings(settings, output: output)

        return settings
    }

    func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.activeFormat.isVideoHDRSupported {
            // Enable HDR for quality and balanced modes, disable for fast mode
            device.automaticallyAdjustsVideoHDREnabled = mode != .fast
        }
    }

    func configureOutput(_ output: AVCapturePhotoOutput) {
        output.maxPhotoQualityPrioritization = mode.qualityPrioritization

        // Enable fast capture for speed mode
        if mode == .fast {
            if output.isResponsiveCaptureSupported {
                output.isResponsiveCaptureEnabled = true
            }
            if output.isFastCapturePrioritizationSupported {
                output.isFastCapturePrioritizationEnabled = true
            }
        }
    }
}
