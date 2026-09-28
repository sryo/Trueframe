// Scorer that returns preset scores instead of running Vision.

import UIKit
@testable import Trueframe

actor FakePhotoScorer: PhotoScoring {
    private var presetScores: [Float] = []
    private(set) var callCount = 0

    private var holdsScores = false
    private var scoreGate: CheckedContinuation<Void, Never>?

    func setScores(_ scores: [Float]) {
        presetScores = scores
    }

    /// Preset scores in order; images beyond the preset get the unscorable score.
    func scores(for images: [UIImage?]) async -> [Float] {
        callCount += 1
        let result = images.indices.map { index in
            index < presetScores.count ? presetScores[index] : CurationPolicy.unscorableScore
        }
        if holdsScores {
            await withCheckedContinuation { scoreGate = $0 }
        }
        return result
    }

    /// Makes scores(for:) suspend, like a slow Vision pass, until releaseScores().
    func holdScores() {
        holdsScores = true
    }

    func releaseScores() {
        holdsScores = false
        scoreGate?.resume()
        scoreGate = nil
    }
}
