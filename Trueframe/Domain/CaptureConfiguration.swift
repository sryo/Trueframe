// Immutable snapshot of capture settings for one session.

/// Settings are snapshotted at session start so mid-session changes
/// to the bindable settings objects can't affect a running capture.
struct CaptureConfiguration: Equatable, Sendable {
    /// Flash forces slow, non-deferrable captures, so it only applies
    /// at relaxed cadences.
    static let minimumFlashInterval = 1.0

    let lens: BackCameraType
    let flashEnabled: Bool
    let interval: Double

    /// Whether flash should actually fire, after applying the burst rule.
    var resolvedFlashEnabled: Bool {
        flashEnabled && interval >= Self.minimumFlashInterval
    }
}
