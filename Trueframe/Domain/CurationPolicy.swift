// Session limits and photo selection rules.

enum CurationPolicy {
    static let maxPhotosPerSession = 50
    static let maxConsecutiveDarkFrames = 3
    static let qualityThreshold: Float = 0.4
    /// Score assigned when a photo can't be scored (no preview, Vision failure).
    /// Sits above the threshold on purpose: unscorable photos are saved, not dropped.
    static let unscorableScore: Float = 0.5

    /// Indices of the photos worth saving: everything at or above the quality
    /// threshold, or the single best photo if nothing passes.
    static func selectionIndices(scores: [Float]) -> [Int] {
        let passing = scores.indices.filter { scores[$0] >= qualityThreshold }
        if passing.isEmpty, let best = scores.indices.max(by: { scores[$0] < scores[$1] }) {
            return [best]
        }
        return passing
    }
}
