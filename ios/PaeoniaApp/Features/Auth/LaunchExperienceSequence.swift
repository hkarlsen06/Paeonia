import Foundation

/// Pure state machine for the cold-launch intro that picks up where the system
/// launch screen leaves off: the petal halves pull apart under tension, snap back,
/// and fade out entirely as they begin to collide — and that collision instant sets
/// off the circular shockwave that unmasks the app surface underneath.
///
/// Kept free of SwiftUI so the one rule that actually matters here is unit-testable:
/// never reveal before *both* the spring has landed *and* the first real app surface
/// behind the overlay is ready. That way the intro always plays in full, but we never
/// flash raw, half-loaded content just because the animation got there first (or hold
/// on a blank screen because content got there first).
struct LaunchExperienceSequence: Equatable {
    enum Phase: Equatable {
        /// Petal mark composed and centered — exactly matching the system launch screen.
        case mark
        /// The spring is playing: the halves pull apart, then collapse back to the impact.
        case spring
        /// The impact happened; the shockwave is unmasking the app surface.
        case revealing
        /// The reveal finished; the launch overlay can be removed.
        case finished
    }

    private(set) var phase: Phase = .mark

    /// The first real app surface behind the launch overlay has loaded, or reached a
    /// final unavailable/error state. We never reveal before this is true.
    private(set) var isContentReady = false

    /// The spring's release has reached the collision instant — the moment the
    /// halves begin to collide, by which point they have faded out entirely.
    private(set) var hasSpringLanded = false

    /// Advances from the composed-mark frame into the spring. A no-op once the spring
    /// has already begun, so a late call can't replay it.
    mutating func beginSpring() {
        guard phase == .mark else {
            return
        }

        phase = .spring
    }

    /// Records that the routed content is ready and starts the reveal if the spring
    /// has also landed. Safe to call before the spring has even begun (fast launches);
    /// the reveal still waits for the impact.
    mutating func markContentReady() {
        isContentReady = true
        beginRevealIfReady()
    }

    /// Records that the spring landed and starts the reveal if content is also ready.
    /// Otherwise we keep holding on the landed mark — a branded wait beats a blank
    /// one — until content arrives.
    mutating func markSpringLanded() {
        hasSpringLanded = true
        beginRevealIfReady()
    }

    /// Completes the reveal once the shockwave has played out, releasing the overlay.
    mutating func finishReveal() {
        guard phase == .revealing else {
            return
        }

        phase = .finished
    }

    private mutating func beginRevealIfReady() {
        guard phase == .spring, isContentReady, hasSpringLanded else {
            return
        }

        phase = .revealing
    }
}
