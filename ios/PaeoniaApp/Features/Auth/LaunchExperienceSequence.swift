import Foundation

/// Pure state machine for the cold-launch intro that picks up where the system
/// launch screen leaves off: the petal mark lifts to reveal the wordmark, the pair
/// holds for a beat, then the app is unmasked with an expanding reveal.
///
/// Kept free of SwiftUI so the one rule that actually matters here is unit-testable:
/// never unmask before *both* the scripted branded hold has played *and* the first
/// real app surface behind the overlay is ready. That way the intro always plays in
/// full, but we never flash raw, half-loaded content just because the animation got
/// there first (or hold on a blank screen because content got there first).
struct LaunchExperienceSequence: Equatable {
    enum Phase: Equatable {
        /// Petal only, centered — exactly matching the system launch screen.
        case mark
        /// Petal lifted and the wordmark revealed; holding before the unmask.
        case wordmark
        /// The app is being unmasked (the reveal is playing).
        case unmasking
        /// The reveal finished; the launch overlay can be removed.
        case finished
    }

    private(set) var phase: Phase = .mark

    /// The first real app surface behind the launch overlay has loaded, or reached a
    /// final unavailable/error state. We never unmask before this is true.
    private(set) var isContentReady = false

    /// The scripted branded hold (mark → wordmark → pause) has elapsed.
    private(set) var hasHeldWordmark = false

    /// Advances from the petal-only frame into the revealed wordmark. A no-op once
    /// the reveal has already happened, so a late call can't replay it.
    mutating func revealWordmark() {
        guard phase == .mark else {
            return
        }

        phase = .wordmark
    }

    /// Records that the routed content is ready and starts the unmask if the hold is
    /// also done. Safe to call before the wordmark has even been revealed (fast
    /// launches); the unmask still waits for the scripted beats.
    mutating func markContentReady() {
        isContentReady = true
        beginUnmaskIfReady()
    }

    /// Records that the branded hold finished and starts the unmask if content is
    /// also ready. Otherwise we keep holding on the wordmark — a branded wait beats a
    /// blank one — until content arrives.
    mutating func markWordmarkHoldElapsed() {
        hasHeldWordmark = true
        beginUnmaskIfReady()
    }

    /// Completes the unmask once its animation has played out, releasing the overlay.
    mutating func finishUnmask() {
        guard phase == .unmasking else {
            return
        }

        phase = .finished
    }

    private mutating func beginUnmaskIfReady() {
        guard phase == .wordmark, isContentReady, hasHeldWordmark else {
            return
        }

        phase = .unmasking
    }
}
