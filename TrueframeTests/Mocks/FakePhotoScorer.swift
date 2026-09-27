// Scorer that returns preset scores instead of running Vision.

import UIKit
@testable import Trueframe

actor FakePhotoScorer: PhotoScoring {
    private var presetScores: [Float] = []

    func setScores(_ scores: [Float]) {
        presetScores = scores
    }

    /// Preset scores in order; images beyond the preset get the unscorable score.
    func scores(for images: [UIImage?]) async -> [Float] {
        images.indices.map { index in
            index < presetScores.count ? presetScores[index] : CurationPolicy.unscorableScore
        }
    }
}
