// Scores photo previews for automatic selection.

import UIKit
import Vision

struct PhotoScorer: Sendable {
    /// Returns a 0-1 aesthetics score per image, in order. Images that can't
    /// be scored get `CurationPolicy.unscorableScore`. Requests run concurrently.
    func scores(for images: [UIImage?]) async -> [Float] {
        await withTaskGroup(of: (Int, Float).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    (index, await Self.score(image))
                }
            }

            var result = [Float](repeating: CurationPolicy.unscorableScore, count: images.count)
            for await (index, score) in group {
                result[index] = score
            }
            return result
        }
    }

    private static func score(_ image: UIImage?) async -> Float {
        guard let cgImage = image?.cgImage else { return CurationPolicy.unscorableScore }
        do {
            let request = CalculateImageAestheticsScoresRequest()
            let observation = try await request.perform(on: cgImage)
            // overallScore is -1...1; normalize to 0...1 for the curation threshold
            return (observation.overallScore + 1) / 2
        } catch {
            return CurationPolicy.unscorableScore
        }
    }
}
