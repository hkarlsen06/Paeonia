import Testing
@testable import PaeoniaApp

/// Covers the cold-launch intro's gating rule: the app is only revealed once *both*
/// the spring has landed *and* the first real surface is ready, no matter which of
/// the two finishes first. Getting this wrong either flashes a half-loaded screen or
/// holds on a blank one.
struct LaunchExperienceSequenceTests {
    @Test func startsOnTheMarkMatchingTheSystemSplash() {
        let sequence = LaunchExperienceSequence()

        #expect(sequence.phase == .mark)
        #expect(sequence.isContentReady == false)
        #expect(sequence.hasSpringLanded == false)
    }

    @Test func beginSpringMovesFromMarkToSpring() {
        var sequence = LaunchExperienceSequence()

        sequence.beginSpring()

        #expect(sequence.phase == .spring)
    }

    @Test func beginSpringOnlyAppliesFromTheMarkPhase() {
        var sequence = LaunchExperienceSequence()
        sequence.beginSpring()
        sequence.markContentReady()
        sequence.markSpringLanded()
        #expect(sequence.phase == .revealing)

        // A late, stray spring start must not knock an in-progress reveal back.
        sequence.beginSpring()

        #expect(sequence.phase == .revealing)
    }

    @Test func landingBeforeContentReadyKeepsHoldingOnTheLandedMark() {
        var sequence = LaunchExperienceSequence()
        sequence.beginSpring()

        sequence.markSpringLanded()

        // Content is still loading, so we keep showing the branded mark.
        #expect(sequence.phase == .spring)

        sequence.markContentReady()

        #expect(sequence.phase == .revealing)
    }

    @Test func contentReadyBeforeLandingStillWaitsForTheImpact() {
        var sequence = LaunchExperienceSequence()
        sequence.beginSpring()

        sequence.markContentReady()

        // The reveal must not jump in early just because content loaded fast.
        #expect(sequence.phase == .spring)

        sequence.markSpringLanded()

        #expect(sequence.phase == .revealing)
    }

    @Test func contentReadyDuringTheMarkPhaseDoesNotSkipTheSpring() {
        var sequence = LaunchExperienceSequence()

        // A very fast launch can be ready before the spring has even begun; the
        // spring must still play rather than jumping straight to the reveal.
        sequence.markContentReady()
        #expect(sequence.phase == .mark)

        sequence.beginSpring()
        #expect(sequence.phase == .spring)

        // The reveal only begins once the impact reports in.
        sequence.markSpringLanded()
        #expect(sequence.phase == .revealing)
    }

    @Test func finishOnlyCompletesAnInProgressReveal() {
        var sequence = LaunchExperienceSequence()

        // Finishing before the reveal has begun is a no-op.
        sequence.finishReveal()
        #expect(sequence.phase == .mark)

        sequence.beginSpring()
        sequence.markSpringLanded()
        sequence.markContentReady()
        #expect(sequence.phase == .revealing)

        sequence.finishReveal()
        #expect(sequence.phase == .finished)
    }

    @Test func repeatedSignalsAreIdempotent() {
        var sequence = LaunchExperienceSequence()
        sequence.beginSpring()
        sequence.markContentReady()
        sequence.markContentReady()
        sequence.markSpringLanded()
        sequence.markSpringLanded()

        #expect(sequence.phase == .revealing)

        sequence.finishReveal()
        sequence.finishReveal()

        #expect(sequence.phase == .finished)
    }
}
