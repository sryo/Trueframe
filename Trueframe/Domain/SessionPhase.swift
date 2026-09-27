/// The single source of truth for where a capture session is in its lifecycle.
///
/// Legal transitions:
/// - idle -> capturing            (proximity covered)
/// - capturing -> ending          (proximity lifted, dark frames, limit, low storage)
/// - ending -> celebrating        (photos exist)
/// - ending -> idle               (nothing captured)
/// - celebrating -> saving        (tumble animation complete)
/// - saving -> idle               (photos curated; the library write finishes on its own)
enum SessionPhase: Equatable, Sendable {
    case idle
    case capturing
    /// Teardown: the engine is draining in-flight captures.
    case ending
    case celebrating
    case saving
}
