// Vision framework integration for smart photo analysis and selection.
// Scores photos based on face quality, aesthetics, and technical factors.

import CoreImage
import UIKit
import Vision

/// Photo quality metrics from Vision analysis
struct PhotoQualityScore: Sendable {
    let overallScore: Float        // Combined score 0-1
    let faceQuality: Float?        // Face capture quality 0-1 (nil if no faces)
    let aestheticsScore: Float     // Vision aesthetics score 0-1
    let hasFaces: Bool             // Whether faces were detected
    let faceCount: Int             // Number of faces detected
    let primaryFaceConfidence: Float?  // Confidence of primary face detection

    /// Whether this photo passes minimum quality threshold
    var meetsMinimumQuality: Bool {
        overallScore >= 0.3 && aestheticsScore >= 0.2
    }

    /// Whether this is a high-quality photo worth featuring
    var isHighQuality: Bool {
        overallScore >= 0.7
    }
}

/// Result of lens smudge detection
struct LensSmudgeResult: Sendable {
    let isSmudged: Bool
    let confidence: Float  // 0-1, higher = more likely smudged
}

/// Analyzes photos using Vision framework for intelligent selection.
actor PhotoAnalyzer {
    static let shared = PhotoAnalyzer()

    // MARK: - Single Photo Analysis

    /// Analyze a single photo and return quality metrics
    func analyze(_ image: UIImage) async -> PhotoQualityScore {
        guard let cgImage = image.cgImage else {
            return PhotoQualityScore(
                overallScore: 0.5,
                faceQuality: nil,
                aestheticsScore: 0.5,
                hasFaces: false,
                faceCount: 0,
                primaryFaceConfidence: nil
            )
        }

        async let faceResults = detectFaces(in: cgImage)
        async let aesthetics = calculateAesthetics(in: cgImage)

        let (faces, aestheticsScore) = await (faceResults, aesthetics)

        // Calculate overall score combining face quality and aesthetics
        let faceQuality = faces.bestFaceQuality
        let faceWeight: Float = faces.hasFaces ? 0.4 : 0.0
        let aestheticsWeight: Float = faces.hasFaces ? 0.6 : 1.0

        var overallScore: Float = aestheticsScore * aestheticsWeight
        if let fq = faceQuality {
            overallScore += fq * faceWeight
        }

        return PhotoQualityScore(
            overallScore: overallScore,
            faceQuality: faceQuality,
            aestheticsScore: aestheticsScore,
            hasFaces: faces.hasFaces,
            faceCount: faces.count,
            primaryFaceConfidence: faces.primaryConfidence
        )
    }

    // MARK: - Aesthetics Analysis (iOS 18+)

    /// Calculate image aesthetics score using Vision framework
    private func calculateAesthetics(in cgImage: CGImage) async -> Float {
        guard #available(iOS 18.0, *) else {
            // Fallback for older iOS versions
            return await legacyAestheticsScore(in: cgImage)
        }

        do {
            let request = CalculateImageAestheticsScoresRequest()
            let observation = try await request.perform(on: cgImage)
            return observation.overallScore
        } catch {
            // Fallback on error
            return await legacyAestheticsScore(in: cgImage)
        }
    }

    /// Legacy aesthetics calculation for iOS < 18
    private func legacyAestheticsScore(in cgImage: CGImage) async -> Float {
        async let sharpness = measureSharpness(in: cgImage)
        async let brightness = measureBrightness(in: cgImage)
        let (s, b) = await (sharpness, brightness)
        return (s + b) / 2.0
    }

    // MARK: - Lens Smudge Detection (iOS 26+)

    /// Detect if the camera lens is smudged
    func detectLensSmudge(_ image: UIImage, threshold: Float = 0.7) async -> LensSmudgeResult {
        guard #available(iOS 26.0, *),
              let cgImage = image.cgImage else {
            return LensSmudgeResult(isSmudged: false, confidence: 0)
        }

        do {
            let request = DetectLensSmudgeRequest()
            let observation = try await request.perform(on: cgImage)
            let confidence = observation.confidence
            return LensSmudgeResult(
                isSmudged: confidence >= threshold,
                confidence: confidence
            )
        } catch {
            return LensSmudgeResult(isSmudged: false, confidence: 0)
        }
    }

    // MARK: - Batch Analysis

    /// Analyze multiple photos and return sorted by quality
    func analyzeAndRank(_ images: [UIImage]) async -> [(image: UIImage, score: PhotoQualityScore)] {
        var results: [(UIImage, PhotoQualityScore)] = []

        for image in images {
            let score = await analyze(image)
            results.append((image, score))
        }

        // Sort by overall score, highest first
        return results.sorted { $0.1.overallScore > $1.1.overallScore }
    }

    // MARK: - Face Detection

    private struct FaceAnalysisResult {
        let hasFaces: Bool
        let count: Int
        let bestFaceQuality: Float?
        let primaryConfidence: Float?
    }

    private func detectFaces(in cgImage: CGImage) async -> FaceAnalysisResult {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceCaptureQualityRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNFaceObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: FaceAnalysisResult(
                        hasFaces: false,
                        count: 0,
                        bestFaceQuality: nil,
                        primaryConfidence: nil
                    ))
                    return
                }

                // Find the best face quality score
                let qualities = observations.compactMap { $0.faceCaptureQuality }
                let bestQuality = qualities.max()
                let primaryConfidence = observations.first?.confidence

                continuation.resume(returning: FaceAnalysisResult(
                    hasFaces: true,
                    count: observations.count,
                    bestFaceQuality: bestQuality,
                    primaryConfidence: primaryConfidence
                ))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: FaceAnalysisResult(
                    hasFaces: false,
                    count: 0,
                    bestFaceQuality: nil,
                    primaryConfidence: nil
                ))
            }
        }
    }

    // MARK: - Sharpness Analysis

    private func measureSharpness(in cgImage: CGImage) async -> Float {
        // Use Laplacian variance as sharpness metric
        let ciImage = CIImage(cgImage: cgImage)

        let context = CIContext()

        // Apply edge detection filter
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return 0.5 }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)

        guard let edgeImage = edgeFilter.outputImage else { return 0.5 }

        // Calculate average intensity of edges
        let extentVector = CIVector(
            x: edgeImage.extent.origin.x,
            y: edgeImage.extent.origin.y,
            z: edgeImage.extent.size.width,
            w: edgeImage.extent.size.height
        )

        guard let areaAverageFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        areaAverageFilter.setValue(edgeImage, forKey: kCIInputImageKey)
        areaAverageFilter.setValue(extentVector, forKey: kCIInputExtentKey)

        guard let avgImage = areaAverageFilter.outputImage else { return 0.5 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(avgImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        // Normalize edge intensity to 0-1 score
        let intensity = Float(bitmap[0]) / 255.0
        return min(intensity * 3.0, 1.0) // Scale up since edges are typically low intensity
    }

    // MARK: - Brightness Analysis

    private func measureBrightness(in cgImage: CGImage) async -> Float {
        let ciImage = CIImage(cgImage: cgImage)

        let context = CIContext()
        let extent = ciImage.extent

        // Calculate average brightness
        let extentVector = CIVector(
            x: extent.origin.x,
            y: extent.origin.y,
            z: extent.size.width,
            w: extent.size.height
        )

        guard let areaAverageFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        areaAverageFilter.setValue(ciImage, forKey: kCIInputImageKey)
        areaAverageFilter.setValue(extentVector, forKey: kCIInputExtentKey)

        guard let avgImage = areaAverageFilter.outputImage else { return 0.5 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(avgImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        // Calculate luminance
        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        // Score based on how close to ideal brightness (0.5 is ideal)
        // Too dark or too bright gets penalized
        let deviation = abs(luminance - 0.5)
        return 1.0 - (deviation * 2.0)
    }
}
